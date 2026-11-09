import ChirograCore
import Foundation

// Enumeraciones que los modelos guardan como texto (`…Raw`). Viven fuera de los esquemas: los esquemas congelados
// (`SchemaV1`, `SchemaV2`, `SchemaV3`) las usan para sus valores por defecto y la app, por los modelos de `SchemaV4`.
// No cambiar el `rawValue` de un caso existente: está guardado en los libros y en iCloud.

// MARK: - Enums persistidos como texto

public enum EntityType: String, CaseIterable, Sendable, Codable {
    case soleProprietorship, llc, sCorp, cCorp, partnership
}

public enum EntryStatus: String, Sendable, Codable {
    case draft, posted
}

public enum InvoiceStatus: String, CaseIterable, Sendable, Codable {
    case draft, sent, partiallyPaid, paid, void
}

public enum BillStatus: String, CaseIterable, Sendable, Codable {
    case open, partiallyPaid, paid, void
}

public enum PaymentMethod: String, CaseIterable, Sendable, Codable {
    case cash, check, bankTransfer, card, other
}

public enum DocumentKind: String, CaseIterable, Sendable, Codable {
    case journalEntry, invoice, creditNote
    /// Nuevo en el esquema 2: serie `E-0001` de los estimados.
    case estimate

    /// Prefijo y dígitos con que se crea la serie si aún no existe (p. ej. empresas dadas de alta con el esquema 1).
    public var defaultFormat: (prefix: String, firstNumber: Int, minimumDigits: Int) {
        switch self {
        case .journalEntry: ("", 1, 1)
        case .invoice: ("F-", 1001, 4)
        case .creditNote: ("NC-", 1, 4)
        case .estimate: ("E-", 1, 4)
        }
    }
}

public enum FilingFrequency: String, CaseIterable, Sendable, Codable {
    case monthly, quarterly, annual
}

// MARK: Nuevos en el esquema 2

/// Cada cuánto se repite una plantilla recurrente.
public enum RecurrenceFrequency: String, CaseIterable, Sendable, Codable {
    case weekly, monthly, quarterly, annual

    /// Unidad y número de unidades entre dos repeticiones.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .annual: (.year, 1)
        }
    }
}

/// Qué documento genera una plantilla recurrente.
public enum RecurringKind: String, CaseIterable, Sendable, Codable {
    /// Gasto pagado al momento (`Expense`).
    case expense
    /// Factura por pagar (`Bill`).
    case bill
}

/// Estado guardado de un estimado. «Vencido» también se deriva (`Estimate.effectiveStatus(asOf:)`).
public enum EstimateStatus: String, CaseIterable, Sendable, Codable {
    case draft, sent, accepted, declined, expired, converted
}

/// Tipo de evento en el historial de envíos de una factura.
public enum InvoiceEventKind: String, CaseIterable, Sendable, Codable {
    case sent, reminder
}

/// Regla de origen del sales tax (informativa en el MVP: la tasa la elige el usuario, DISEÑO §4.8).
public enum SalesTaxSourcing: String, CaseIterable, Sendable, Codable {
    /// Se cobra la tasa del lugar del negocio (p. ej. Texas para ventas dentro del estado).
    case origin
    /// Se cobra la tasa del lugar de entrega.
    case destination
}

/// Estilo de la plantilla de factura (canvas `AjustesPlantilla`).
public enum InvoiceStyle: String, CaseIterable, Sendable, Codable {
    case classic, compact
}

/// Colores de acento predefinidos de la plantilla de factura (canvas `AjustesPlantilla`).
/// En `Company.invoiceAccentHex` se guarda el hexadecimal, así que también cabe un color libre.
public enum InvoiceAccent: String, CaseIterable, Sendable {
    case ink, graphite, copper, petroleum, forest

    public var hex: String {
        switch self {
        case .ink: "#3A3FD1"
        case .graphite: "#12142B"
        case .copper: "#B4500F"
        case .petroleum: "#0E6A86"
        case .forest: "#2F6B4F"
        }
    }

    /// Fondo suave para cabeceras de tabla en el PDF.
    public var softHex: String {
        switch self {
        case .ink: "#E7E8FB"
        case .graphite: "#ECEEF5"
        case .copper: "#FCEBDD"
        case .petroleum: "#DCEFF5"
        case .forest: "#E1F0E7"
        }
    }

    public init?(hex: String) {
        guard let match = Self.allCases.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }) else { return nil }
        self = match
    }
}
