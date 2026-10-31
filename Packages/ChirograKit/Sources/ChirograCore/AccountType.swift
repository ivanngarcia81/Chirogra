import Foundation

/// Lado en el que una cuenta aumenta su saldo.
public enum NormalBalance: String, Sendable, Codable {
    case debit
    case credit
}

/// Los cinco tipos fundamentales de cuenta (§4.1).
public enum AccountType: String, CaseIterable, Sendable, Codable {
    case asset
    case liability
    case equity
    case income
    case expense

    public var normalBalance: NormalBalance {
        switch self {
        case .asset, .expense: .debit
        case .liability, .equity, .income: .credit
        }
    }

    /// `true` si aparece en el balance general; `false` si aparece en el estado de resultados.
    public var isBalanceSheet: Bool {
        switch self {
        case .asset, .liability, .equity: true
        case .income, .expense: false
        }
    }

    /// Saldo con signo positivo cuando la cuenta está en su lado normal.
    public func naturalBalance(debit: Int64, credit: Int64) -> Int64 {
        normalBalance == .debit ? debit - credit : credit - debit
    }
}

/// Subtipos que determinan el comportamiento de la cuenta y su sección en los reportes.
public enum AccountSubtype: String, CaseIterable, Sendable, Codable {
    // Activo
    case cash
    case bank
    case accountsReceivable
    case undepositedFunds
    case inventory
    case otherCurrentAsset
    case fixedAsset
    case otherAsset
    // Pasivo
    case accountsPayable
    case creditCard
    case salesTaxPayable
    case otherCurrentLiability
    case longTermLiability
    // Patrimonio
    case ownersEquity
    case ownersDraw
    case retainedEarnings
    case openingBalanceEquity
    // Ingreso
    case sales
    /// Descuentos y devoluciones sobre ventas: cuenta de ingreso que se carga (resta de los ingresos).
    case salesDiscount
    case otherIncome
    // Gasto
    case costOfGoodsSold
    case operatingExpense
    case otherExpense

    public var accountType: AccountType {
        switch self {
        case .cash, .bank, .accountsReceivable, .undepositedFunds, .inventory,
             .otherCurrentAsset, .fixedAsset, .otherAsset:
            .asset
        case .accountsPayable, .creditCard, .salesTaxPayable, .otherCurrentLiability, .longTermLiability:
            .liability
        case .ownersEquity, .ownersDraw, .retainedEarnings, .openingBalanceEquity:
            .equity
        case .sales, .salesDiscount, .otherIncome:
            .income
        case .costOfGoodsSold, .operatingExpense, .otherExpense:
            .expense
        }
    }

    /// Cuentas donde puede entrar o salir dinero (destino de cobros, origen de pagos y gastos).
    public var isMoneyAccount: Bool {
        switch self {
        case .cash, .bank, .undepositedFunds, .creditCard: true
        default: false
        }
    }
}
