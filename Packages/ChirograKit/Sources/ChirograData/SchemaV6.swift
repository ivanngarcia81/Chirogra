import ChirograCore
import Foundation
import SwiftData

// Esquema 6.0.0 (25-nov-2026, versión 1.4; docs/PLAN-1.4.md §1 y §3, docs/DATOS-V6.md). Solo añade modelos, con valor
// por defecto u opcional en todo: CloudKit lo admite y la migración es ligera. Los demás modelos son los del 5 (los del 4
// salvo `AuditEvent` y `BankTransaction`), sin cambios.
// - `Appointment`: la agenda.
// - `EstimatedTaxSetting` y `EstimatedTaxPayment`: el apartado para impuestos estimados (1040-ES). El ajuste va en un
//   modelo propio y no en `Company`: `Company` tiene relación con `Attachment` (el logo) y cambiarla obligaría a cambiar
//   también esa y las que cuelgan de ella.
//
// Sin relaciones: la cita guarda el `id` del cliente, de la factura y del presupuesto (como `BankTransaction` guarda los
// suyos). Una relación obligaría a añadir su inversa en `Customer` o `Invoice`, que cambiarían de clase en este esquema.
//
// **Citas que se repiten** (decisión del usuario del 16-nov): la primera cita guarda la regla (`recurrenceRaw`,
// `recurrenceEnd`) y las demás se calculan (`AppointmentRecurrence`). Solo se guarda una repetición cuando cambia:
// hecha, cancelada, movida o facturada. Esa copia lleva `seriesID` (la cita con la regla) y `occurrenceStart` (la fecha
// que sustituye). «Esta y las siguientes» corta la regla el día antes y empieza una serie nueva.

public enum SchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    /// Los modelos que este esquema añade (la migración 3 → 4 trabaja sin ellos: `CompanyOwnership.ownedTypesV4`).
    static let addedTypes: Set<ObjectIdentifier> = [
        ObjectIdentifier(Appointment.self), ObjectIdentifier(EstimatedTaxSetting.self), ObjectIdentifier(EstimatedTaxPayment.self),
    ]

    public static var models: [any PersistentModel.Type] {
        SchemaV5.models + [Appointment.self, EstimatedTaxSetting.self, EstimatedTaxPayment.self]
    }

    /// Una cita con un cliente (o sin cliente todavía): qué, cuándo, dónde y cómo terminó.
    @Model
    public final class Appointment {
        public var id: UUID = UUID()
        /// Empresa a la que pertenece (`Company.id`). `nil` = registro huérfano: cuenta como de la empresa principal.
        public var companyID: UUID?
        /// Cliente (`Customer.id`); `nil` para una cita sin cliente todavía.
        public var customerID: UUID?
        /// Servicio o título («Instalación de repisas»).
        public var title: String = ""
        public var start: Date = Date()
        public var durationMinutes: Int = 60
        public var location: String = ""
        public var notes: String = ""
        public var statusRaw: String = AppointmentStatus.scheduled.rawValue
        /// Minutos antes para el aviso; `-1` = sin aviso (`AppointmentReminder`).
        public var reminderMinutes: Int = 30
        /// Regla de repetición, solo en la primera cita de una serie (`AppointmentRepeat`; vacío = no se repite).
        public var recurrenceRaw: String = ""
        /// Último día en que puede caer una repetición; `nil` = no termina.
        public var recurrenceEnd: Date?
        /// En una repetición guardada aparte: la cita que tiene la regla.
        public var seriesID: UUID?
        /// En una repetición guardada aparte: el inicio que tenía según la regla (la fecha que sustituye).
        public var occurrenceStart: Date?
        /// Factura o presupuesto creados desde la cita.
        public var invoiceID: UUID?
        public var estimateID: UUID?
        public var createdAt: Date = Date()

        // En una sola línea: `scripts/gen-backup.py` lee así los inicializadores.
        public init(title: String, start: Date, durationMinutes: Int = 60, customerID: UUID? = nil) {
            self.title = title
            self.start = start
            self.durationMinutes = durationMinutes
            self.customerID = customerID
        }

        public var status: AppointmentStatus {
            get { AppointmentStatus(rawValue: statusRaw) ?? .scheduled }
            set { statusRaw = newValue.rawValue }
        }

        public var recurrence: AppointmentRepeat {
            get { AppointmentRepeat(rawValue: recurrenceRaw) ?? .none }
            set { recurrenceRaw = newValue.rawValue }
        }

        public var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
        /// La primera cita de una serie (tiene la regla).
        public var isSeries: Bool { recurrence != .none && seriesID == nil }
        /// Una repetición guardada aparte.
        public var isOccurrenceOverride: Bool { seriesID != nil }
        public var isInvoiced: Bool { invoiceID != nil }
    }

    /// El apartado para impuestos de una empresa: el porcentaje y si la tarjeta sale en Inicio y Reportes. Uno por
    /// empresa; si dos aparatos crearon uno cada uno antes de sincronizar, vale el más antiguo.
    @Model
    public final class EstimatedTaxSetting {
        public var id: UUID = UUID()
        public var companyID: UUID?
        public var percent: Int = 25
        public var showsCard: Bool = true
        public var createdAt: Date = Date()

        public init(percent: Int = 25, showsCard: Bool = true) {
            self.percent = percent
            self.showsCard = showsCard
        }
    }

    /// Un pago de impuestos estimados al IRS: a qué pago del año corresponde y su asiento (de la cuenta de la que salió
    /// a retiros del dueño). Chirogra solo lo anota: el pago se hace con el IRS.
    @Model
    public final class EstimatedTaxPayment {
        public var id: UUID = UUID()
        public var companyID: UUID?
        /// Año fiscal y pago (1…4) del 1040-ES; el 4.º de 2026 se paga en enero de 2027.
        public var taxYear: Int = 0
        public var period: Int = 1
        public var date: Date = Date()
        public var amount: Int64 = 0
        /// Cuenta de dinero de la que salió.
        public var accountID: UUID?
        public var journalEntryID: UUID?
        public var createdAt: Date = Date()

        public init(taxYear: Int, period: Int, date: Date, amount: Int64, accountID: UUID?) {
            self.taxYear = taxYear
            self.period = period
            self.date = date
            self.amount = amount
            self.accountID = accountID
        }
    }
}

extension ChirograMigrationPlan {
    /// Ligera: Core Data crea las tablas nuevas, vacías.
    public static var migrateV5toV6: MigrationStage { .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self) }
}

public typealias Appointment = SchemaV6.Appointment
public typealias EstimatedTaxSetting = SchemaV6.EstimatedTaxSetting
public typealias EstimatedTaxPayment = SchemaV6.EstimatedTaxPayment

extension SchemaV6.Appointment: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<Appointment> {
        let id: UUID? = companyID
        return #Predicate<Appointment> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}

extension SchemaV6.EstimatedTaxSetting: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<EstimatedTaxSetting> {
        let id: UUID? = companyID
        return #Predicate<EstimatedTaxSetting> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}

extension SchemaV6.EstimatedTaxPayment: CompanyOwned {
    public static func ownedBy(_ companyID: UUID, includeOrphans: Bool) -> Predicate<EstimatedTaxPayment> {
        let id: UUID? = companyID
        return #Predicate<EstimatedTaxPayment> { $0.companyID == id || (includeOrphans && $0.companyID == nil) }
    }
}
