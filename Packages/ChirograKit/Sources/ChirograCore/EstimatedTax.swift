import Foundation

// Impuestos estimados (1.4, docs/PLAN-1.4.md §3; canvas «Chirogra 1.4», tableros `Apartado`, `PagoIRS`): los cuatro
// pagos al IRS del formulario 1040-ES. Los periodos no son trimestres de calendario:
//   1.º ene–mar → 15 abr · 2.º abr–may → 15 jun · 3.º jun–ago → 15 sep · 4.º sep–dic → 15 ene del año siguiente.
// Si el día 15 cae en sábado o domingo, vence el lunes (los feriados no se cuentan).

public enum EstimatedTaxCalendar {
    /// Uno de los cuatro pagos de un año fiscal.
    public struct Period: Hashable, Sendable {
        public let year: Int
        /// 1…4.
        public let number: Int
        /// Primer instante del periodo.
        public let start: Date
        /// Primer instante después del periodo (exclusivo).
        public let end: Date
        /// Día en que vence el pago (a las 00:00).
        public let due: Date
    }

    /// Mes en que empieza cada periodo y mes (del mismo año o del siguiente) en que vence.
    private static let layout: [(startMonth: Int, endMonth: Int, dueMonth: Int, dueNextYear: Bool)] = [
        (1, 4, 4, false), (4, 6, 6, false), (6, 9, 9, false), (9, 13, 1, true),
    ]

    public static func periods(of year: Int, calendar: Calendar) -> [Period] {
        layout.enumerated().compactMap { index, item in
            guard let start = calendar.date(from: DateComponents(year: year, month: item.startMonth, day: 1)),
                  let end = calendar.date(from: DateComponents(year: year, month: item.endMonth, day: 1)),
                  let fifteenth = calendar.date(from: DateComponents(year: item.dueNextYear ? year + 1 : year, month: item.dueMonth, day: 15))
            else { return nil }
            return Period(year: year, number: index + 1, start: start, end: end, due: nextWeekday(fifteenth, calendar: calendar))
        }
    }

    /// El periodo en que cae `date`.
    public static func period(containing date: Date, calendar: Calendar) -> Period? {
        periods(of: calendar.component(.year, from: date), calendar: calendar).first { $0.start <= date && date < $0.end }
    }

    /// El pago que toca atender hoy: el del periodo de hoy, salvo que el anterior aún no venza (del 1 al 15 de enero, el
    /// 4.º del año pasado; del 1 al 15 de abril, el 1.º…) y no esté pagado.
    public static func focus(today: Date, isPaid: (Period) -> Bool, calendar: Calendar) -> Period? {
        guard let current = period(containing: today, calendar: calendar) else { return nil }
        let day = calendar.startOfDay(for: today)
        if let previous = self.previous(of: current, calendar: calendar), day <= previous.due, !isPaid(previous) {
            return previous
        }
        return current
    }

    public static func previous(of period: Period, calendar: Calendar) -> Period? {
        period.number > 1
            ? periods(of: period.year, calendar: calendar)[period.number - 2]
            : periods(of: period.year - 1, calendar: calendar).last
    }

    /// Cuánto apartar: `percent` % de la ganancia, redondeado al centavo; nada si no hubo ganancia.
    public static func setAside(profit: Int64, percent: Int) -> Int64 {
        guard profit > 0, percent > 0 else { return 0 }
        return profit.multiplied(by: Int64(percent), dividedRoundingHalfAwayFromZeroBy: 100)
    }

    private static func nextWeekday(_ date: Date, calendar: Calendar) -> Date {
        var day = date
        while calendar.isDateInWeekend(day) { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        return day
    }
}
