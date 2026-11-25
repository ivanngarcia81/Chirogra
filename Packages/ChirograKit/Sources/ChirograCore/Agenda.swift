import Foundation

// Agenda (1.4, docs/PLAN-1.4.md §1): los estados y la repetición de una cita, y el cálculo de las repeticiones. Sin
// SwiftData: lo usan el modelo (`SchemaV6.Appointment`), `Bookkeeper+Agenda` y las pruebas.
// No cambiar el `rawValue` de un caso existente: está guardado en los libros y en iCloud.

/// Cómo terminó una cita (canvas «Chirogra 1.4»: programada, hecha, cancelada, no vino).
public enum AppointmentStatus: String, CaseIterable, Sendable, Codable {
    case scheduled, done, cancelled, noShow
    /// Una repetición borrada («Eliminar solo esta»): la regla la seguiría dando, así que se guarda tachada. No se ve.
    case removed
}

/// Cada cuánto se repite una cita (decisión del usuario del 16-nov).
public enum AppointmentRepeat: String, CaseIterable, Sendable, Codable {
    case none = ""
    case daily, weekly, biweekly, monthly
}

/// El aviso antes de la cita, en minutos (`Appointment.reminderMinutes`).
public enum AppointmentReminder {
    /// Sin aviso.
    public static let none = -1
    /// Las opciones del editor: a la hora, 15 y 30 minutos, 1 hora y 1 día antes.
    public static let choices = [none, 0, 15, 30, 60, 1_440]
}

/// Las repeticiones de una regla, calculadas: la serie guarda solo la primera cita.
public enum AppointmentRecurrence {
    /// Inicio de la repetición `index` (0 = la primera cita). Los meses se cuentan desde la primera, no uno tras otro:
    /// una cita del 31 cae el 30 de noviembre y vuelve al 31 en diciembre.
    public static func start(of index: Int, from first: Date, rule: AppointmentRepeat, calendar: Calendar) -> Date? {
        switch rule {
        case .none: index == 0 ? first : nil
        case .daily: calendar.date(byAdding: .day, value: index, to: first)
        case .weekly: calendar.date(byAdding: .day, value: 7 * index, to: first)
        case .biweekly: calendar.date(byAdding: .day, value: 14 * index, to: first)
        case .monthly: calendar.date(byAdding: .month, value: index, to: first)
        }
    }

    /// Los inicios de las repeticiones que empiezan dentro de `range` (`start ≤ inicio < end`). `lastDay`: el último
    /// día en que puede caer una (incluido); `nil` = sin fin.
    public static func starts(from first: Date, rule: AppointmentRepeat, lastDay: Date?, in range: DateInterval,
                              calendar: Calendar) -> [Date] {
        let limit = lastDay.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        guard rule != .none else {
            return range.start <= first && first < range.end && (limit.map { first < $0 } ?? true) ? [first] : []
        }
        // Salta directo cerca del principio del rango: una serie diaria de hace años no recorre cada día.
        var index = 0
        if range.start > first {
            let days = calendar.dateComponents([.day], from: first, to: range.start).day ?? 0
            let months = calendar.dateComponents([.month], from: first, to: range.start).month ?? 0
            index = switch rule {
            case .none: 0
            case .daily: max(0, days - 1)
            case .weekly: max(0, days / 7 - 1)
            case .biweekly: max(0, days / 14 - 1)
            case .monthly: max(0, months - 1)
            }
        }
        var result: [Date] = []
        while let date = start(of: index, from: first, rule: rule, calendar: calendar), date < range.end {
            if let limit, date >= limit { break }
            if date >= range.start { result.append(date) }
            index += 1
            if index > 100_000 { break }
        }
        return result
    }
}
