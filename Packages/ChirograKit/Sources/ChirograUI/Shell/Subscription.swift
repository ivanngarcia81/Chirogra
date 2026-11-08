import ChirograData
import StoreKit
import SwiftUI

/// Suscripción de Chirogra (App Store, StoreKit 2): un solo plan mensual con 14 días de prueba gratis (oferta de
/// introducción). El precio lo pone App Store Connect, no el código: lanzamiento a $24.99 los 3 primeros meses y luego
/// $29.99 para los nuevos, conservando el precio a los ya suscritos. La misma suscripción vale en iPhone, iPad y Mac
/// (mismo identificador de app).
///
/// Sin suscripción (la prueba terminó o nunca empezó; `canStartTrial` distingue los avisos) los libros quedan en
/// **solo lectura** (`Bookkeeper.isReadOnly`):
/// se ven, se exportan y se sacan copias de seguridad, pero no se registra nada nuevo. Mientras el producto no exista en
/// App Store Connect (`notConfigured`: antes de publicar, en las copias de prueba) no se bloquea nada.
@MainActor
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()
    static let productID = "com.chirogra.app.mensual"
    /// Se encontró el producto alguna vez: desde entonces, sin conexión también se aplica la suscripción.
    private static let configuredKey = "subscriptionStoreConfigured"

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
    /// Pantalla de suscripción a la vista (la abre la raíz).
    var showsPaywall = false
    @ObservationIgnored private var updates: Task<Void, Never>?

    var isReadOnly: Bool { status == .lapsed }

    /// Consulta la App Store y escucha las compras, renovaciones y reembolsos (también los de otros aparatos).
    func start() {
        guard updates == nil else { return }
        #if DEBUG
        // `-qa.suscripcion prueba|activa|vencida` (solo Debug): el estado sin preguntar a la App Store.
        switch UserDefaults.standard.string(forKey: "qa.suscripcion") {
        case "prueba": status = .subscribed(isTrial: true, expires: Calendar.current.date(byAdding: .day, value: 14, to: .now)); return
        case "activa": status = .subscribed(isTrial: false, expires: Calendar.current.date(byAdding: .month, value: 1, to: .now)); return
        case "vencida": status = .lapsed; return
        case "nueva": status = .lapsed; canStartTrial = true; return
        default: break
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
        if let found = try? await Product.products(for: [Self.productID]).first {
            product = found
            UserDefaults.standard.set(true, forKey: Self.configuredKey)
        }
        guard product != nil || UserDefaults.standard.bool(forKey: Self.configuredKey) else {
            status = .notConfigured
            return
        }
        var current: StoreKit.Transaction?
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                current = transaction
            }
        }
        if let current {
            status = .subscribed(isTrial: current.offer?.type == .introductory && current.offer?.paymentMode == .freeTrial,
                                 expires: current.expirationDate)
        } else {
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

/// Pantalla de suscripción (StoreKit): qué incluye Chirogra, el plan mensual con su prueba de 14 días, «Restaurar
/// compras» y los enlaces legales. La «×» del sistema la cierra (los libros siguen en solo lectura si no hay suscripción).
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = SubscriptionStore.shared

    var body: some View {
        Group {
            SubscriptionStoreView(productIDs: [SubscriptionStore.productID]) {
                VStack(spacing: 14) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Palette.brand)
                        .accessibilityHidden(true)
                    Text("Chirogra").font(.largeTitle.bold()).foregroundStyle(Palette.ink)
                    Text("Tus libros completos en tu iPhone, iPad y Mac: facturas, gastos, sales tax y reportes, privados en tu cuenta.")
                        .font(.body).multilineTextAlignment(.center).foregroundStyle(Palette.ink2)
                    VStack(alignment: .leading, spacing: 8) {
                        feature("checkmark.seal", "14 días gratis; cancela cuando quieras")
                        feature("doc.text", "Facturas, estimados y cobros")
                        feature("chart.bar.xaxis", "Estado de resultados, balance y sales tax")
                        feature("lock.shield", "Sin servidores: tus datos en tus aparatos e iCloud")
                    }
                    .padding(.top, 4)
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
                if !store.isReadOnly { dismiss() }
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
                        Text("Chirogra").foregroundStyle(Palette.ink)
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
