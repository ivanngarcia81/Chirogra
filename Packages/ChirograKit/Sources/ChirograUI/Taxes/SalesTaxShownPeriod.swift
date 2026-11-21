import ChirograData
import Foundation

/// Periodo de declaración que muestra Impuestos (y la fecha de Inicio), según la frecuencia de la agencia: un mes, un
/// trimestre o un año. Antes la pantalla era siempre trimestral y «Periodo de declaración» no cambiaba nada (Eric,
/// Beta Family, build 55). Las fechas salen de `Bookkeeper.salesTaxFilingPeriod`, las mismas de los avisos.
struct SalesTaxShownPeriod: Equatable {
    let frequency: FilingFrequency
    let filing: SalesTaxFilingPeriod
    var calendar: Calendar = .current

    /// El periodo que contiene `date` desplazado `offset` periodos (0 el actual, −1 el anterior…).
    init(_ frequency: FilingFrequency, offset: Int = 0, now: Date = .now, calendar: Calendar = .current) {
        self.frequency = frequency
        self.calendar = calendar
        let periods = Bookkeeper.salesTaxFilingPeriods(frequency, containing: now, count: max(-offset, 0) + 1, calendar: calendar)
        filing = periods.last ?? Bookkeeper.salesTaxFilingPeriod(frequency, containing: now, calendar: calendar)
    }

    /// Del primer día al siguiente al último (para el resumen y los pagos).
    var interval: DateInterval {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: filing.end)) ?? filing.end
        return DateInterval(start: filing.start, end: max(end, filing.start))
    }

    /// Fecha límite: el día 20 del mes siguiente al periodo.
    var deadline: Date { filing.deadline }

    private var year: String { filing.start.formatted(.appDateTime.year()) }

    private var quarterNumber: Int { (calendar.component(.month, from: filing.start) - 1) / 3 + 1 }

    /// «oct–dic».
    private var quarterMonths: String {
        (interval.start..<interval.end.addingTimeInterval(-1)).formatted(.interval.month(.abbreviated).locale(.appText))
    }

    /// Menú y subtítulo: «Noviembre de 2026», «T4 2026 · oct–dic», «2026».
    var title: String {
        switch frequency {
        case .monthly: filing.start.monthYear
        case .quarterly: String(localized: "\(name) · \(quarterMonths)")
        case .annual: year
        }
    }

    /// Dentro de una frase («Cobrado en …», «Declaración …»): «noviembre de 2026», «T4 2026», «2026».
    var name: String {
        switch frequency {
        case .monthly: filing.start.formatted(.appDateTime.month(.wide).year())
        case .quarterly: String(localized: "T\(quarterNumber) \(year)")
        case .annual: year
        }
    }

    /// Encabezado de la columna de la tabla de tasas («T4 cobrado»): corto, cabe en 110 pt.
    var columnName: String {
        switch frequency {
        case .monthly: filing.start.shortMonth.sentenceCased
        case .quarterly: String(localized: "T\(quarterNumber)")
        case .annual: year
        }
    }

    /// «Desglose · …»: «noviembre de 2026», «oct–dic 2026», «2026».
    var range: String {
        switch frequency {
        case .monthly: name
        case .quarterly: "\(quarterMonths) \(year)"
        case .annual: year
        }
    }

    /// Subtítulo de la pantalla: «Noviembre de 2026 · declaración mensual».
    var subtitle: String {
        switch frequency {
        case .monthly: String(localized: "\(title) · declaración mensual")
        case .quarterly: String(localized: "\(title) · declaración trimestral")
        case .annual: String(localized: "\(title) · declaración anual")
        }
    }

    /// Etiqueta del menú de periodos.
    var pickerLabel: String {
        switch frequency {
        case .monthly: String(localized: "Mes")
        case .quarterly: String(localized: "Trimestre")
        case .annual: String(localized: "Año")
        }
    }

    /// Pie de «Pagado» en las cajas de iPad y Mac.
    func paymentsFoot(hasPayments: Bool) -> String {
        switch (frequency, hasPayments) {
        case (.monthly, true): String(localized: "Pagos del mes")
        case (.monthly, false): String(localized: "Sin pagos en el mes")
        case (.quarterly, true): String(localized: "Pagos del trimestre")
        case (.quarterly, false): String(localized: "Sin pagos en el trimestre")
        case (.annual, true): String(localized: "Pagos del año")
        case (.annual, false): String(localized: "Sin pagos en el año")
        }
    }
}
