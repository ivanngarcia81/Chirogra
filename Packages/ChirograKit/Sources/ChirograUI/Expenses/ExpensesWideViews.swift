import ChirograCore
import ChirograData
import SwiftData
import SwiftUI

extension Bill {
    /// Abierta y con el vencimiento ya pasado.
    var isOverdue: Bool { isOpen && dueDate < Calendar.current.startOfDay(for: .now) }
}
