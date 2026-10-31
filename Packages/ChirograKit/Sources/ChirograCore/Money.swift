import Foundation

/// Código de moneda ISO 4217 con el número de decimales de su unidad mínima.
public struct CurrencyCode: Hashable, Sendable, Codable {
    public let code: String
    public let minorUnitDigits: Int

    public init(code: String, minorUnitDigits: Int = 2) {
        self.code = code
        self.minorUnitDigits = minorUnitDigits
    }

    public static let usd = CurrencyCode(code: "USD")

    /// 10^minorUnitDigits (100 para USD).
    public var minorUnitsPerMajor: Int64 {
        var value: Int64 = 1
        for _ in 0..<minorUnitDigits { value *= 10 }
        return value
    }
}

/// Importe exacto en unidades mínimas (centavos). Nunca se usa `Double` para dinero.
public struct Money: Hashable, Sendable, Codable, Comparable {
    public var minorUnits: Int64
    public var currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode = .usd) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    /// Convierte un `Decimal` (p. ej. lo que escribe el usuario) redondeando a la unidad mínima, mitad hacia arriba.
    public init(decimal: Decimal, currency: CurrencyCode = .usd) {
        var scaled = decimal * Decimal(currency.minorUnitsPerMajor)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        self.init(minorUnits: NSDecimalNumber(decimal: rounded).int64Value, currency: currency)
    }

    public static func zero(_ currency: CurrencyCode = .usd) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    public var decimalValue: Decimal {
        Decimal(minorUnits) / Decimal(currency.minorUnitsPerMajor)
    }

    public var isZero: Bool { minorUnits == 0 }

    public func formatted(locale: Locale = .current) -> String {
        decimalValue.formatted(.currency(code: currency.code).locale(locale))
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "No se pueden sumar monedas distintas")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "No se pueden restar monedas distintas")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits, currency: value.currency)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "No se pueden comparar monedas distintas")
        return lhs.minorUnits < rhs.minorUnits
    }
}

extension Int64 {
    /// División entera redondeando la mitad lejos de cero (convención contable habitual).
    @inlinable
    public func dividedRoundingHalfAwayFromZero(by divisor: Int64) -> Int64 {
        precondition(divisor > 0, "El divisor debe ser positivo")
        let quotient = self / divisor
        let remainder = self % divisor
        if Swift.abs(remainder) * 2 >= divisor {
            return self >= 0 ? quotient + 1 : quotient - 1
        }
        return quotient
    }
}
