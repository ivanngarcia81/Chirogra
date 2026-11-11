import ChirograCore
import Foundation
import SwiftData

// Esquema 5.0.0 (10-nov-2026, versión 1.2; docs/DATOS-V5.md). Dos modelos ganan propiedades, todas con valor por
// defecto, así que CloudKit lo admite y la migración es ligera:
// - `AuditEvent` (la bitácora de cambios): `device`, el aparato en que se hizo el cambio, y `changeDetails`, el antes y
//   el después de cada campo («Correo: ana@x.com → ana@y.com», una línea por campo);
// - `BankTransaction`: `ignoreReason`, el motivo con que se excluyó el movimiento de la bandeja.
//
// Lo demás de la 1.2 no cambia el esquema: los asientos de ajuste del contador son un origen nuevo del asiento
// (`EntrySource.accountantAdjustment`, se guarda como texto y una versión anterior lo ve como manual) y un movimiento
// dividido crea un gasto o un depósito con varias líneas.
//
// Los demás modelos son los de `SchemaV4`, sin cambios: este esquema los reutiliza (como el 3 reutilizó los del 2).
// Ninguno de los dos tiene relaciones, así que ningún otro modelo tiene que cambiar de clase. Sus versiones de
// `SchemaV4` quedan congeladas (solo propiedades guardadas; `FrozenSchemaTests`).

public enum SchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        SchemaV4.models.map { model in
            switch ObjectIdentifier(model) {
            case ObjectIdentifier(SchemaV4.AuditEvent.self): AuditEvent.self
            case ObjectIdentifier(SchemaV4.BankTransaction.self): BankTransaction.self
            default: model
            }
        }
    }

    /// Un cambio de la bitácora: qué se hizo (`action`), a qué (`subjectEntity` + `entityID`), un resumen, el detalle
    /// campo por campo y el aparato. Se guarda al hacer el cambio, en el mismo guardado (`Bookkeeper.audit`).
    @Model
    public final class AuditEvent {
        public var id: UUID = UUID()
        /// Empresa a la que pertenece (`Company.id`). `nil` = registro huérfano: cuenta como de la empresa principal.
        public var companyID: UUID?
        public var date: Date = Date()
        /// Quién lo hizo, si se sabe («Ejemplo» para los datos de ejemplo). Con usuarios (2.0, con servidor), la persona.
        public var actor: String = ""
        /// La entidad a la que se refiere el evento («Company», «Invoice»…). En el esquema 2 era `entityName`, que
        /// chocaba con `CD_entityName` en CloudKit (`SchemaV3.swift`).
        public var subjectEntity: String = ""
        public var entityID: UUID?
        public var action: String = ""
        public var summary: String = ""
        /// Esquema 5: nombre del aparato en que se hizo («iPhone de Iván»). Vacío en los de antes de la 1.2.
        public var device: String = ""
        /// Esquema 5: antes y después de cada campo que cambió, una línea por campo («Correo: a@x.com → b@x.com»), o lo
        /// que tenía lo borrado. Vacío si no hay detalle.
        public var changeDetails: String = ""

        // En una sola línea: `scripts/gen-backup.py` lee así los inicializadores.
        public init(actor: String, entityName: String, entityID: UUID?, action: String, summary: String, device: String = "", changeDetails: String = "") {
            self.actor = actor
            self.subjectEntity = entityName
            self.entityID = entityID
            self.action = action
            self.summary = summary
            self.device = device
            self.changeDetails = changeDetails
        }

        /// Las líneas del detalle, sin vacías.
        public var detailLines: [String] {
            changeDetails.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
    }

    /// Movimiento de un extracto bancario o de tarjeta, venga de donde venga (`BankTransactionSource`: CSV, OFX/QFX y,
    /// en el futuro, Plaid). Nace «por revisar» y termina emparejado con una línea del diario, categorizado (se creó
    /// un gasto, cobro o transferencia desde él) o ignorado.
    ///
    /// **Signo de `amount`:** el efecto en la cuenta contable vista como debe − haber. En un banco, positivo = depósito
    /// y negativo = cargo; en una tarjeta, negativo = compra (aumenta la deuda) y positivo = pago o devolución.
    @Model
    public final class BankTransaction {
        public var id: UUID = UUID()
        public var companyID: UUID?
        /// Cuenta contable de banco o tarjeta a la que pertenece el extracto.
        public var accountID: UUID?
        public var date: Date = Date()
        public var amount: Int64 = 0
        /// Descripción tal como viene del banco («UBER *TRIP HELP.UBER.COM»).
        public var details: String = ""
        /// Beneficiario o pagador, si el extracto lo separa (OFX `NAME`) o si una regla lo puso.
        public var payee: String = ""
        public var memo: String = ""
        public var checkNumber: String = ""
        /// Identificador del banco (OFX `FITID`) o, si el CSV no trae uno, un hash estable de fecha, importe y
        /// descripción (`BankStatementLine.stableID`). Con él no se importa dos veces lo mismo.
        public var externalID: String = ""
        public var sourceRaw: String = BankSourceKind.csv.rawValue
        public var statusRaw: String = BankTransactionStatus.toReview.rawValue
        /// Cuenta (de gasto, ingreso…) propuesta por una regla o elegida por el usuario para categorizarlo. En uno
        /// dividido, la de la parte mayor (las partes son las líneas del documento creado).
        public var categoryAccountID: UUID?
        public var vendorID: UUID?
        public var customerID: UUID?
        /// Regla que lo categorizó, si alguna.
        public var ruleID: UUID?
        /// Asiento y línea del diario con que quedó emparejado (la línea es la de `accountID`).
        public var matchedEntryID: UUID?
        public var matchedLineID: UUID?
        /// Documento creado desde el movimiento (gasto, cobro, asiento de transferencia).
        public var createdDocumentID: UUID?
        /// Importación en la que llegó (todas las líneas de un archivo comparten el mismo).
        public var importBatchID: UUID?
        public var importedAt: Date = Date()
        public var reviewedAt: Date?
        /// Esquema 5: por qué se excluyó («Duplicado», «Personal»…). Vacío si no se excluyó o no se dio motivo.
        public var ignoreReason: String = ""

        public init(accountID: UUID?, date: Date, amount: Int64, details: String, externalID: String, source: BankSourceKind) {
            self.accountID = accountID
            self.date = date
            self.amount = amount
            self.details = details
            self.externalID = externalID
            self.sourceRaw = source.rawValue
        }

        public var status: BankTransactionStatus {
            get { BankTransactionStatus(rawValue: statusRaw) ?? .toReview }
            set { statusRaw = newValue.rawValue }
        }

        public var source: BankSourceKind { BankSourceKind(rawValue: sourceRaw) ?? .csv }
        /// Entra dinero (depósito, o pago/devolución en una tarjeta).
        public var isInflow: Bool { amount > 0 }
        public var isPending: Bool { status == .toReview }
    }
}

extension ChirograMigrationPlan {
    /// Ligera: Core Data añade `device`, `changeDetails` e `ignoreReason` con su valor por defecto (cadena vacía).
    public static var migrateV4toV5: MigrationStage { .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self) }
}
