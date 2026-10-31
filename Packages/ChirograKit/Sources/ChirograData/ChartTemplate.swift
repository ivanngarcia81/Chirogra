import ChirograCore
import Foundation

/// Sector del negocio: decide la plantilla del plan de cuentas (DISEÑO §3.1 y §4.1).
public enum BusinessSector: String, CaseIterable, Sendable, Codable {
    case services, retail, construction

    public var title: String {
        switch self {
        case .services: "Servicios"
        case .retail: "Comercio"
        case .construction: "Construcción y oficios"
        }
    }

    public var summary: String {
        switch self {
        case .services: "Consultoría, diseño, salud, educación, agencias…"
        case .retail: "Tienda física o en línea que vende productos con inventario."
        case .construction: "Contratistas, remodelación, electricistas, plomeros…"
        }
    }

    public var template: ChartTemplate {
        switch self {
        case .services: .usServices
        case .retail: .usRetail
        case .construction: .usConstruction
        }
    }
}

/// Plantillas de plan de cuentas para pequeños negocios en EE. UU. (DISEÑO §4.1).
/// Categorías de gasto alineadas con las líneas del Schedule C; nombres y numeración propios de Chirogra.
public struct ChartTemplate: Sendable {
    public struct Entry: Sendable {
        public var code: String
        public var spanish: String
        public var english: String
        public var subtype: AccountSubtype
        public var isSystem: Bool

        init(_ code: String, _ spanish: String, _ english: String, _ subtype: AccountSubtype, system: Bool = false) {
            self.code = code
            self.spanish = spanish
            self.english = english
            self.subtype = subtype
            self.isSystem = system
        }

        public func name(for locale: Locale) -> String {
            locale.language.languageCode?.identifier == "es" ? spanish : english
        }
    }

    public var entries: [Entry]

    public static let usServices = ChartTemplate(entries: [
        // 1000 Activos
        Entry("1000", "Caja", "Cash on Hand", .cash),
        Entry("1010", "Cuenta corriente", "Checking", .bank),
        Entry("1020", "Cuenta de ahorro", "Savings", .bank),
        Entry("1090", "Fondos no depositados", "Undeposited Funds", .undepositedFunds, system: true),
        Entry("1100", "Cuentas por cobrar", "Accounts Receivable", .accountsReceivable, system: true),
        Entry("1300", "Gastos pagados por adelantado", "Prepaid Expenses", .otherCurrentAsset),
        Entry("1500", "Equipo y herramientas", "Equipment", .fixedAsset),
        Entry("1510", "Vehículos", "Vehicles", .fixedAsset),
        Entry("1590", "Depreciación acumulada", "Accumulated Depreciation", .fixedAsset),
        // 2000 Pasivos
        Entry("2000", "Cuentas por pagar", "Accounts Payable", .accountsPayable, system: true),
        Entry("2100", "Tarjeta de crédito", "Credit Card", .creditCard),
        Entry("2200", "Sales tax por pagar", "Sales Tax Payable", .salesTaxPayable, system: true),
        Entry("2300", "Nómina por pagar", "Payroll Liabilities", .otherCurrentLiability),
        Entry("2700", "Préstamos", "Loans Payable", .longTermLiability),
        // 3000 Patrimonio
        Entry("3000", "Capital del dueño", "Owner's Equity", .ownersEquity, system: true),
        Entry("3100", "Retiros del dueño", "Owner's Draw", .ownersDraw),
        Entry("3200", "Resultados acumulados", "Retained Earnings", .retainedEarnings, system: true),
        Entry("3900", "Saldos de apertura", "Opening Balance Equity", .openingBalanceEquity, system: true),
        // 4000 Ingresos
        Entry("4000", "Ingresos por servicios", "Service Revenue", .sales),
        Entry("4100", "Venta de productos y materiales", "Product & Materials Sales", .sales),
        Entry("4900", "Descuentos y devoluciones", "Discounts & Refunds", .salesDiscount, system: true),
        Entry("7000", "Otros ingresos", "Other Income", .otherIncome),
        Entry("7010", "Intereses ganados", "Interest Earned", .otherIncome),
        // 5000 Costo de ventas
        Entry("5000", "Materiales y suministros del trabajo", "Job Materials", .costOfGoodsSold),
        Entry("5100", "Subcontratistas", "Subcontractors", .costOfGoodsSold),
        // 6000 Gastos operativos (Schedule C)
        Entry("6000", "Publicidad y marketing", "Advertising & Marketing", .operatingExpense),
        Entry("6050", "Vehículo y transporte", "Car & Truck", .operatingExpense),
        Entry("6100", "Comisiones y cargos bancarios", "Bank & Merchant Fees", .operatingExpense),
        Entry("6150", "Contratistas independientes", "Contract Labor", .operatingExpense),
        Entry("6200", "Seguros", "Insurance", .operatingExpense),
        Entry("6250", "Intereses pagados", "Interest Expense", .operatingExpense),
        Entry("6300", "Honorarios legales y profesionales", "Legal & Professional Fees", .operatingExpense),
        Entry("6350", "Gastos de oficina", "Office Expenses", .operatingExpense),
        Entry("6400", "Alquiler", "Rent or Lease", .operatingExpense),
        Entry("6450", "Reparaciones y mantenimiento", "Repairs & Maintenance", .operatingExpense),
        Entry("6500", "Suministros", "Supplies", .operatingExpense),
        Entry("6550", "Impuestos y licencias", "Taxes & Licenses", .operatingExpense),
        Entry("6600", "Viajes", "Travel", .operatingExpense),
        Entry("6650", "Comidas de negocio", "Business Meals", .operatingExpense),
        Entry("6700", "Servicios públicos", "Utilities", .operatingExpense),
        Entry("6750", "Software y suscripciones", "Software & Subscriptions", .operatingExpense),
        Entry("6800", "Teléfono e internet", "Phone & Internet", .operatingExpense),
        Entry("6850", "Sueldos y salarios", "Wages", .operatingExpense),
        Entry("6900", "Depreciación", "Depreciation", .operatingExpense),
        Entry("8000", "Otros gastos", "Other Expenses", .otherExpense),
    ])

    /// Comercio: inventario, ventas de mercancía y su costo.
    public static let usRetail = usServices.replacing([
        Entry("4000", "Ventas de mercancía", "Merchandise Sales", .sales),
        Entry("4100", "Ventas en línea", "Online Sales", .sales),
        Entry("5000", "Costo de mercancía vendida", "Cost of Goods Sold", .costOfGoodsSold),
        Entry("5100", "Fletes y envíos de compra", "Freight In", .costOfGoodsSold),
    ]).adding([
        Entry("1200", "Inventario", "Inventory", .inventory),
        Entry("6120", "Comisiones de plataformas de venta", "Marketplace Fees", .operatingExpense),
    ])

    /// Construcción y oficios: ingresos por obra, subcontratistas, equipo y retenciones.
    public static let usConstruction = usServices.replacing([
        Entry("4000", "Ingresos por obra", "Construction Revenue", .sales),
        Entry("4100", "Materiales facturados", "Billed Materials", .sales),
    ]).adding([
        Entry("1150", "Retenciones por cobrar (retainage)", "Retainage Receivable", .otherCurrentAsset),
        Entry("5200", "Renta de equipo para obra", "Equipment Rental", .costOfGoodsSold),
        Entry("5300", "Permisos y licencias de obra", "Job Permits", .costOfGoodsSold),
    ])

    func replacing(_ replacements: [Entry]) -> ChartTemplate {
        ChartTemplate(entries: entries.map { entry in replacements.first { $0.code == entry.code } ?? entry })
    }

    func adding(_ extra: [Entry]) -> ChartTemplate {
        ChartTemplate(entries: (entries + extra).sorted { $0.code < $1.code })
    }
}
