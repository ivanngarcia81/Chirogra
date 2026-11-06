import ChirograCore
import Foundation

/// Las cuentas que se ofrecen como «Categoría» al registrar un gasto, una factura por pagar o una recurrente
/// (recorrido «cliente nuevo», 5-nov: el menú empezaba por «1150 · Retenciones por cobrar» y «1590 · Depreciación
/// acumulada»).
///
/// - `costs`: gastos y costo de ventas (`AccountType.expense`), primero y en el orden recibido (por código).
/// - `assetPurchases`: aparte y al final, solo los activos que se compran con un pago: equipo y vehículos
///   (`fixedAsset`), pagos por adelantado (`otherCurrentAsset`) e inventario.
///
/// Nunca salen las cuentas de dinero, las por cobrar (también la retención o *retainage*), las contra-cuentas
/// (depreciación o amortización acumulada, estimación de incobrables) ni el gasto de depreciación, que solo se
/// registra con un asiento de ajuste. El esquema no marca las contra-cuentas, así que se reconocen por el nombre, en
/// español y en inglés, sin distinguir mayúsculas ni acentos.
public struct ExpenseCategoryGroups {
    public var costs: [Account]
    public var assetPurchases: [Account]

    public var isEmpty: Bool { costs.isEmpty && assetPurchases.isEmpty }
    /// Hay inventario entre los activos (plantilla de comercio): cambia el título del grupo.
    public var includesInventory: Bool { assetPurchases.contains { $0.subtype == .inventory } }
}

public enum ExpenseCategories {
    /// Subtipos de activo que tiene sentido «comprar» con un gasto.
    public static let purchasableAssetSubtypes: Set<AccountSubtype> = [.fixedAsset, .otherCurrentAsset, .inventory]

    /// Trozos de nombre que delatan una cuenta que nunca es la categoría de una compra.
    static let excludedNameFragments = [
        "acumulad", "accumulated",                       // depreciación/amortización acumulada
        "por cobrar", "receivable", "retainage", "retencion", // cuentas por cobrar y retenciones
        "incobrable", "doubtful", "allowance",           // estimación de incobrables
    ]

    /// Gasto que no se paga: lo registra un asiento de ajuste.
    static let nonCashExpenseFragments = ["depreciacion", "depreciation", "amortizacion", "amortization"]

    /// Agrupa `accounts` (en su orden) para el selector de categoría. Solo cuentas activas sin subcuentas. Si
    /// `keeping` es una cuenta que no pasaría el filtro (un gasto antiguo, la categoría por defecto de un proveedor),
    /// se añade igualmente al final de su grupo para que el selector no se quede en blanco.
    public static func groups(from accounts: [Account], keeping selectedID: UUID? = nil) -> ExpenseCategoryGroups {
        var costs: [Account] = []
        var assets: [Account] = []
        for account in accounts where account.isPostable {
            if isCost(account) { costs.append(account) } else if isAssetPurchase(account) { assets.append(account) }
        }
        if let selectedID, let kept = accounts.first(where: { $0.id == selectedID }),
           !costs.contains(where: { $0.id == selectedID }), !assets.contains(where: { $0.id == selectedID }) {
            if kept.type == .expense { costs.append(kept) } else { assets.append(kept) }
        }
        return ExpenseCategoryGroups(costs: costs, assetPurchases: assets)
    }

    /// Gasto o costo de ventas que se paga (no la depreciación).
    public static func isCost(_ account: Account) -> Bool {
        account.type == .expense && !matches(account.name, nonCashExpenseFragments)
    }

    /// Equipo, vehículos, pagos por adelantado o inventario; no las contra-cuentas ni las por cobrar.
    public static func isAssetPurchase(_ account: Account) -> Bool {
        purchasableAssetSubtypes.contains(account.subtype) && !matches(account.name, excludedNameFragments)
    }

    private static func matches(_ name: String, _ fragments: [String]) -> Bool {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return fragments.contains { folded.contains($0) }
    }
}
