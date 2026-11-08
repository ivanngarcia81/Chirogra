import ChirograData
import StoreKit
import SwiftUI

/// Suscripción de Chirogra (App Store, StoreKit 2), dos planes mensuales en el grupo «Chirogra», con 14 días de prueba
/// gratis (oferta de introducción):
/// - **Chirogra** (`com.chirogra.app.mensual`): una empresa. Lanzamiento a $24.99 los 3 primeros meses y luego $29.99
///   para los nuevos, conservando el precio a los ya suscritos.
/// - **Chirogra para contadores** (`com.chirogra.app.contador.mensual`, nivel superior del grupo): hasta 5 empresas
///   (`CompanyLimits.accountant`). Precio por decidir (en `App/Chirogra.storekit`, $99.99 solo para probar).
/// Los precios los pone App Store Connect, no el código. La misma suscripción vale en iPhone, iPad y Mac (mismo
/// identificador de app). El plan fija `Bookkeeper.companyLimit` (las archivadas cuentan, decisión del 8-nov).
///
/// Sin suscripción (la prueba terminó o nunca empezó; `canStartTrial` distingue los avisos) los libros quedan en
/// **solo lectura** (`Bookkeeper.isReadOnly`):
/// se ven, se exportan y se sacan copias de seguridad, pero no se registra nada nuevo. Mientras el producto no exista en
/// App Store Connect (`notConfigured`: antes de publicar, en las copias de prueba) no se bloquea nada; y mientras no exista
/// el plan para contadores, tampoco el número de empresas (hasta 5: no se puede ofrecer un plan que no está a la venta).
@MainActor
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()
    static let productID = "com.chirogra.app.mensual"
    /// Plan para contadores: hasta 5 empresas. Nivel superior del mismo grupo de suscripciones.
    static let accountantProductID = "com.chirogra.app.contador.mensual"
    static let productIDs = [productID, accountantProductID]
    /// Se encontró el producto alguna vez: desde entonces, sin conexión también se aplica la suscripción.
    private static let configuredKey = "subscriptionStoreConfigured"
    /// Igual para el plan para contadores.
    private static let accountantConfiguredKey = "subscriptionAccountantConfigured"

    /// Plan de la suscripción vigente.
    enum Plan: Equatable {
        case standard, accountant
    }

    /// Qué enseña la pantalla de suscripción: los dos planes, o solo el de contadores (al llegar al límite de empresas).
    enum PaywallFocus: Equatable {
        case all, accountant
    }

    enum Status: Equatable {
        /// Todavía no se ha consultado la App Store.
        case unknown
        /// El producto no existe en App Store Connect (antes de publicar): todo abierto.
        case notConfigured
        case subscribed(isTrial: Bool, expires: Date?)
        /// Sin suscripción vigente: solo lectura.
        case lapsed
    }

    private(set) var status: Status = .unknown
    /// Sin suscripción pero con la prueba gratis aún sin usar (nunca se suscribió en esta cuenta de Apple): los avisos
    /// invitan a empezar la prueba en vez de decir que la suscripción terminó.
    private(set) var canStartTrial = false
    private(set) var product: Product?
    private(set) var accountantProduct: Product?
    /// Plan de la suscripción vigente (`.standard` sin suscripción).
    private(set) var plan: Plan = .standard
    /// Pantalla de suscripción a la vista (la abre la raíz).
    var showsPaywall = false
    /// Qué planes enseña la pantalla de suscripción de la raíz.
    var paywallFocus: PaywallFocus = .all
    @ObservationIgnored private var updates: Task<Void, Never>?

    var isReadOnly: Bool { status == .lapsed }

    /// El plan para contadores está a la venta (existe en App Store Connect): se puede ofrecer al llegar al límite.
    var sellsAccountantPlan: Bool {
        accountantProduct != nil || UserDefaults.standard.bool(forKey: Self.accountantConfiguredKey)
    }

    /// Empresas que permite el plan (archivadas incluidas). Sin la suscripción o sin el plan para contadores en App Store
    /// Connect no se bloquea nada (hasta 5); con el plan normal, 1; con el de contadores, 5.
    var companyLimit: Int {
        switch status {
        case .notConfigured: return CompanyLimits.accountant
        case .unknown, .lapsed, .subscribed: break
        }
        if plan == .accountant || !sellsAccountantPlan { return CompanyLimits.accountant }
        return CompanyLimits.standard
    }

    /// Pasa el límite del plan a los libros (`Bookkeeper.companyLimit`).
    private func applyLimit() {
        Bookkeeper.companyLimit = companyLimit
    }

    /// Consulta la App Store y escucha las compras, renovaciones y reembolsos (también los de otros aparatos).
    func start() {
        guard updates == nil else { return }
        #if DEBUG
        // `-qa.suscripcion prueba|activa|vencida` (solo Debug): el estado sin preguntar a la App Store.
        // `contador`: el plan para contadores activo. Con estos argumentos el plan para contadores cuenta como a la venta
        // (con `activa` o `prueba`, el límite es 1 y al pasarlo se ofrece el de contadores).
        let qaStatus: Status?
        switch UserDefaults.standard.string(forKey: "qa.suscripcion") {
        case "prueba": qaStatus = .subscribed(isTrial: true, expires: Calendar.current.date(byAdding: .day, value: 14, to: .now))
        case "activa": qaStatus = .subscribed(isTrial: false, expires: Calendar.current.date(byAdding: .month, value: 1, to: .now))
        case "contador":
            qaStatus = .subscribed(isTrial: false, expires: Calendar.current.date(byAdding: .month, value: 1, to: .now))
            plan = .accountant
        case "vencida": qaStatus = .lapsed
        case "nueva": qaStatus = .lapsed; canStartTrial = true
        default: qaStatus = nil
        }
        if let qaStatus {
            status = qaStatus
            UserDefaults.standard.set(true, forKey: Self.accountantConfiguredKey)
            applyLimit()
            return
        }
        #endif
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        defer { applyLimit() }
        if let found = try? await Product.products(for: Self.productIDs) {
            if let monthly = found.first(where: { $0.id == Self.productID }) {
                product = monthly
                UserDefaults.standard.set(true, forKey: Self.configuredKey)
            }
            if let accountant = found.first(where: { $0.id == Self.accountantProductID }) {
                accountantProduct = accountant
                UserDefaults.standard.set(true, forKey: Self.accountantConfiguredKey)
            }
        }
        guard product != nil || UserDefaults.standard.bool(forKey: Self.configuredKey) else {
            status = .notConfigured
            return
        }
        // La vigente de cualquiera de los dos planes; con las dos (al cambiar de plan), la de contadores.
        var current: StoreKit.Transaction?
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil,
               current?.productID != Self.accountantProductID {
                current = transaction
            }
        }
        if let current {
            plan = current.productID == Self.accountantProductID ? .accountant : .standard
            status = .subscribed(isTrial: current.offer?.type == .introductory && current.offer?.paymentMode == .freeTrial,
                                 expires: current.expirationDate)
        } else {
            plan = .standard
            canStartTrial = await product?.subscription?.isEligibleForIntroOffer ?? false
            status = .lapsed
        }
    }

    /// Hace `action` si se puede registrar; si los libros están en solo lectura, abre la pantalla de suscripción.
    func whenWritable(_ action: () -> Void) {
        if isReadOnly { showsPaywall = true } else { action() }
    }
}

enum ChirograLinks {
    /// Condiciones de uso: las estándar de Apple (EULA) mientras no haya unas propias.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Política de privacidad (`sitio/` en GitHub Pages, chirogra.com): en español o en inglés según el idioma de la app.
    static var privacyPolicy: URL? {
        let spanish = Bundle.main.preferredLocalizations.first?.hasPrefix("es") ?? true
        return URL(string: spanish ? "https://chirogra.com/privacidad/" : "https://chirogra.com/privacy/")
    }
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// Pantalla de suscripción (StoreKit): qué incluye Chirogra, los dos planes mensuales (Chirogra y Chirogra para
/// contadores) con su prueba de 14 días, «Restaurar compras» y los enlaces legales. Al llegar al límite de empresas
/// (`focus: .accountant`) enseña solo el plan para contadores (con el plan normal, StoreKit lo ofrece como mejora). La
/// «×» del sistema la cierra (los libros siguen en solo lectura si no hay suscripción).
struct PaywallView: View {
    var focus: SubscriptionStore.PaywallFocus = .all
    @Environment(\.dismiss) private var dismiss
    private let store = SubscriptionStore.shared

    private var productIDs: [String] {
        focus == .accountant ? [SubscriptionStore.accountantProductID] : SubscriptionStore.productIDs
    }

    var body: some View {
        Group {
            SubscriptionStoreView(productIDs: productIDs) {
                VStack(spacing: 14) {
                    Image(systemName: focus == .accountant ? "building.2.fill" : "book.pages.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.brand)
                        .accessibilityHidden(true)
                    if focus == .accountant {
                        Text("Chirogra para contadores").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                        Text("Tu plan es para una empresa. Con el plan para contadores llevas los libros de hasta 5 empresas, cada una con sus clientes, facturas, impuestos y reportes.")
                            .font(.body).multilineTextAlignment(.center).foregroundStyle(Palette.ink2)
                        VStack(alignment: .leading, spacing: 8) {
                            feature("building.2", "Hasta 5 empresas, cada una con sus libros")
                            feature("arrow.left.arrow.right", "Cambia de empresa desde Inicio o la barra lateral")
                            feature("externaldrive", "Una copia por empresa para entregársela a tu cliente")
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Chirogra").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                        Text("Tus libros completos en tu iPhone, iPad y Mac: facturas, gastos, sales tax y reportes, privados en tu cuenta.")
                            .font(.body).multilineTextAlignment(.center).foregroundStyle(Palette.ink2)
                        VStack(alignment: .leading, spacing: 8) {
                            feature("checkmark.seal", "14 días gratis; cancela cuando quieras")
                            feature("doc.text", "Facturas, estimados y cobros")
                            feature("chart.bar.xaxis", "Estado de resultados, balance y sales tax")
                            feature("lock.shield", "Sin servidores: tus datos en tus aparatos e iCloud")
                            feature("building.2", "Para contadores: hasta 5 empresas")
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(url: ChirograLinks.termsOfUse, for: .termsOfService)
            .modifier(PrivacyPolicyLink())
            .onInAppPurchaseCompletion { _, _ in
                await store.refresh()
                let done = focus == .accountant ? store.plan == .accountant : !store.isReadOnly
                if done { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 620)
        #endif
    }

    private func feature(_ systemImage: String, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).foregroundStyle(Palette.ink) } icon: { Image(systemName: systemImage).foregroundStyle(Palette.brand) }
            .font(.subheadline)
    }
}

private struct PrivacyPolicyLink: ViewModifier {
    func body(content: Content) -> some View {
        if let url = ChirograLinks.privacyPolicy {
            content.subscriptionStorePolicyDestination(url: url, for: .privacyPolicy)
        } else {
            content
        }
    }
}

/// Aviso fijo arriba mientras los libros están en solo lectura, con «Suscribirme».
struct ReadOnlyBanner: View {
    private let store = SubscriptionStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(Palette.warning).accessibilityHidden(true)
            Text(store.canStartTrial
                 ? "Solo lectura: empieza tu prueba gratis de 14 días para registrar. Puedes ver tus libros y sacar copias."
                 : "Solo lectura: tu suscripción terminó. Puedes ver tus libros y sacar copias.")
                .font(.subheadline).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(store.canStartTrial ? "Probar gratis" : "Suscribirme") { store.showsPaywall = true }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brandFill)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.surface)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

/// Mac: el aviso de solo lectura al pie de la barra lateral, encima de la empresa.
struct ReadOnlySidebarNote: View {
    private let store = SubscriptionStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Solo lectura", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            Text(store.canStartTrial
                 ? "Empieza tu prueba gratis de 14 días para registrar. Puedes ver tus libros y sacar copias."
                 : "Tu suscripción terminó. Puedes ver tus libros y sacar copias.")
                .font(.subheadline).foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button(store.canStartTrial ? "Probar gratis" : "Suscribirme") { store.showsPaywall = true }
                .buttonStyle(.borderedProminent).tint(Palette.brandFill).controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 8)
    }
}

/// «Suscripción» en Ajustes › iCloud, copias y seguridad: el estado y «Administrar suscripción» o «Ver planes».
struct SubscriptionSection: View {
    @Environment(\.openURL) private var openURL
    private let store = SubscriptionStore.shared
    #if os(iOS)
    @State private var managing = false
    #endif

    var body: some View {
        if store.status != .notConfigured && store.status != .unknown {
            Section {
                HStack(spacing: 12) {
                    IconTile(systemImage: "star.fill", foreground: store.isReadOnly ? Palette.gray : Palette.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.plan == .accountant && !store.isReadOnly ? "Chirogra para contadores" : "Chirogra")
                            .foregroundStyle(Palette.ink)
                        Text(statusText).font(.footnote).foregroundStyle(store.isReadOnly ? Palette.warning : Palette.ink2)
                    }
                    Spacer(minLength: 8)
                    if store.isReadOnly {
                        Button(store.canStartTrial ? "Probar gratis" : "Ver planes") { store.showsPaywall = true }
                    } else {
                        Button("Administrar") { manage() }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                SectionLabel(text: String(localized: "Suscripción"))
            }
            #if os(iOS)
            .manageSubscriptionsSheet(isPresented: $managing)
            #endif
        }
    }

    private var statusText: String {
        switch store.status {
        case .subscribed(let isTrial, let expires):
            let day = expires?.formatted(date: .abbreviated, time: .omitted) ?? ""
            return isTrial ? String(localized: "Prueba gratis hasta el \(day)") : String(localized: "Activa · se renueva el \(day)")
        case .lapsed:
            return store.canStartTrial ? String(localized: "Prueba gratis de 14 días sin empezar · solo lectura")
                                       : String(localized: "Sin suscripción · solo lectura")
        case .unknown, .notConfigured: return ""
        }
    }

    private func manage() {
        #if os(iOS)
        managing = true
        #else
        openURL(ChirograLinks.manageSubscriptions)
        #endif
    }
}
