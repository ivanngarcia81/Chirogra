# Datos v4: esquema 4.0.0 y servicios de la fase 2 sin servidor

Capa de datos de PLAN-FASE2 (7/8-nov-2026): varias empresas, banca y conciliación, presupuestos, base caja, flujo de
efectivo, deducibles, sales tax por código postal y enlace de pago. **Sin pantallas**: este documento es para los agentes
de pantallas, que usan esta API y no tocan el modelo. Todo vive en `Packages/ChirograKit/Sources/ChirograData`
(`SchemaV4*.swift`, `Bookkeeper+*.swift`) y `ChirograCore` (extractos, flujo de efectivo, presupuesto, formularios).

Reglas que siguen valiendo (DATOS-V2): las vistas no escriben asientos; todo cambio contable pasa por `Bookkeeper`; los
asientos contabilizados son inmutables (editar = revertir + asiento nuevo).

## 0. Esquema 4 y reglas de CloudKit

Lo que se despliega a Producción en CloudKit es para siempre (CONTEXTO, 7-nov). En el esquema 4:
- **Solo se añade**: propiedades nuevas opcionales o con valor por defecto y modelos nuevos con relaciones opcionales e
  inversas; sin `.unique` ni `.deny`. `CloudKitSchemaTests.schema4OnlyAdds` comprueba que nada del esquema 3 se quita,
  se renombra ni cambia de tipo.
- **Nunca renombrar** (tampoco con `originalName`) ni reutilizar nombres; ningún nombre reservado (`entityName`,
  `description`, `recordName`… lista en `CloudKitSchemaTests.noReservedFieldNames`).
- Antes de publicar: `-qa.esquemaCloudKit 1`, desplegar a Producción y **probar en Producción** (lo hace el coordinador).

### Archivos

| Archivo | Qué hay |
|---|---|
| `SchemaV4.swift` | `SchemaV4` (4.0.0, 39 modelos), `ChirograMigrationPlan` (V1→V2→V3→V4), los `typealias` de la app y el protocolo `CompanyOwned` |
| `SchemaV4Models.swift`, `SchemaV4Models2.swift` | Los 33 modelos de siempre, ahora del esquema 4 (con su lógica) |
| `SchemaV4Banking.swift` | Modelos nuevos: banca, conciliación y presupuestos, y sus enums |
| `PersistedEnums.swift` | Enums guardados como texto (salieron de `SchemaV2.swift`) |
| `SchemaV1.swift`, `SchemaV2.swift`, `SchemaV3.swift` | **Congelados** (solo propiedades guardadas). No tocarlos: `FrozenSchemaTests` compara sus hashes con los de las versiones publicadas |

### Propiedades nuevas en modelos que ya existían

| Modelo | Propiedad | Para qué |
|---|---|---|
| Todos salvo `Company` (38) | `companyID: UUID?` | Empresa dueña. `nil` = huérfano (ver §1) |
| `Company` | `sortOrder: Int = 0` | Orden del selector |
| `Company` | `isArchived: Bool = false`, `archivedAt: Date?` | Empresa archivada (no cuenta para el límite) |
| `Company` | `postalCode: String = ""` | ZIP del negocio (sales tax con origen) |
| `Company` | `paymentLinkURL`, `paymentInstructions: String = ""`, `showPayNowOnInvoice: Bool = true` | Enlace de pago propio |
| `Customer` | `postalCode: String = ""` | ZIP de entrega (sales tax con destino) |
| `Account` | `taxFormLineRaw: String = ""` | Línea del Schedule C / 1120-S (vacío = la sugerida) |
| `JournalLine` | `reconciliationID: UUID?`, `clearedAt: Date?` | Conciliación en la que se marcó |

Calculada nueva: `Company.name` (comercial o, si no hay, legal).

### Modelos nuevos

| Modelo | Propiedades |
|---|---|
| `BankTransaction` | `companyID`, `accountID`, `date`, `amount` (Int64 con signo, ver §3), `details`, `payee`, `memo`, `checkNumber`, `externalID`, `sourceRaw` (`BankSourceKind`: csv, ofx, plaid, manual), `statusRaw` (`BankTransactionStatus`: toReview, categorized, matched, ignored), `categoryAccountID`, `vendorID`, `customerID`, `ruleID`, `matchedEntryID`, `matchedLineID`, `createdDocumentID`, `importBatchID`, `importedAt`, `reviewedAt` |
| `BankRule` | `companyID`, `name`, `matchText`, `amountSignRaw` (`BankAmountSign`: any, inflow, outflow), `bankAccountID`, `targetAccountID`, `vendorID`, `payee`, `autoApply`, `priority`, `isActive`, `createdAt` |
| `BankImportProfile` | `companyID`, `accountID`, `name`, `columnsJSON` (`CSVColumnMapping`), `dateFormat`, `amountSignRaw` (`CSVAmountSign`), `delimiter`, `hasHeaderRow`, `createdAt`, `lastUsedAt` |
| `Reconciliation` | `companyID`, `accountID`, `statementDate`, `statementEndingBalance`, `beginningBalance`, `statusRaw` (`ReconciliationStatus`: inProgress, completed), `closedAt`, `createdAt` |
| `Budget` | `companyID`, `name`, `fiscalYear`, `createdAt`, `lines` → `BudgetLine` (cascada) |
| `BudgetLine` | `companyID`, `accountID`, `month` (1–12, natural), `amount`, `budget` |

**Desviaciones del plan** (PLAN-FASE2 «Esquema 4 (propuesta)»), todas aditivas:
- `companyID` también en los **hijos** (líneas, adjuntos, aplicaciones…): así toda `@Query` filtra igual, la copia por
  empresa y el borrado de una empresa son un filtro, y un hijo que llega por iCloud antes que su padre no se pierde.
- `BankTransaction`: además `memo`, `checkNumber`, `categoryAccountID`, `vendorID`, `customerID`, `ruleID`,
  `matchedLineID` (la línea exacta emparejada, no solo el asiento) y `reviewedAt`.
- `BankRule`: además `bankAccountID` (regla de una sola cuenta), `payee` (renombrar), `isActive` y `createdAt`.
- `BankImportProfile`: además `name`, `delimiter`, `hasHeaderRow`, `createdAt`, `lastUsedAt`.
- `Reconciliation.createdAt`; `Company.isArchived`/`archivedAt` (para «archivar una empresa»).
- `EntrySource` gana `bankDeposit` y `transfer` (asientos creados desde el banco). Se guarda como texto: una versión
  anterior los ve como `manual`.

## 1. Varias empresas · `Bookkeeper+Companies.swift`

**Cómo funciona.** Cada `Bookkeeper` trabaja con **una** empresa: la dada (`Bookkeeper(context:actor:companyID:)`) o,
sin ella, la **activa** del aparato (`ActiveCompany.id`, en `UserDefaults` con la clave `ActiveCompany.defaultsKey` =
`"activeCompanyID"`; no se sincroniza) o, si esa no existe en estos libros, la primera del selector. Todo lo que crea
lleva su `companyID` (`insert(_:)`) y todas sus búsquedas filtran por ella (`fetch`, `count`, `scoped`). Así las
pantallas que hacen `Bookkeeper(context: context)` ya trabajan con la empresa activa sin cambiar nada.

**Huérfanos.** Un registro con `companyID == nil` (llegó de un aparato con la 1.0.x, o una pantalla lo insertó con
`context.insert` sin pasar por `Bookkeeper`) cuenta como de la **empresa principal** (la más antigua), que es la única que
conocen las versiones anteriores. Además, al guardar, `Bookkeeper` pone su empresa a lo insertado sin empresa
(`stampInsertedModels`). **La app debe llamar a `adoptOrphanRecords()` al abrirse y tras cada importación de iCloud**
(junto a `runAutomations()`), que lo deja asignado para siempre.

| Servicio | Qué hace |
|---|---|
| `ActiveCompany.id`, `ActiveCompany.select(_:)` | Empresa activa del aparato |
| `Bookkeeper.companyLimit` (estático) | Límite de empresas activas: `CompanyLimits.standard` (1) o `.accountant` (5). Lo pone la app según la suscripción |
| `companies(includeArchived:)` | En el orden del selector (`sortOrder`, después la más antigua) |
| `canAddCompany()` | Cabe otra sin pasar el límite |
| `forNewCompany() -> Bookkeeper` | Un `Bookkeeper` con un id nuevo para dar de alta otra empresa; falla con `companyLimitReached` |
| `setUpCompany(...)` | El alta de siempre. Con un `Bookkeeper` de `forNewCompany()` crea **otra** empresa con ese id; con uno sin `companyID`, solo la primera (si no, `companyAlreadyExists`). **Deja activa la empresa creada**, así el resto del alta (`setUpSalesTax`, `recordOpeningBalances`, `SampleData`…) con `Bookkeeper(context:)` va a la nueva |
| `forCompany(_ id:) -> Bookkeeper` | El mismo `Bookkeeper` para otra empresa |
| `select(_:)`, `reorderCompanies(_:)` | Activa y orden del selector |
| `archiveCompany(_:)`, `unarchiveCompany(_:)` | Archivar (deja sitio en el límite; si era la activa, pasa a la primera) y volver a mostrar (si cabe) |
| `deleteCompany(_:)` | Borra la empresa **y todos sus registros** (y los huérfanos si es la principal) en un guardado. Irreversible: confirmar y ofrecer antes una copia |
| `companyOverviews(includeArchived:asOf:) -> [CompanyOverview]` | Lista con lo pendiente de cada una: por cobrar, vencidas, por pagar, avisos sin leer, movimientos por revisar |
| `adoptOrphanRecords() -> Int` | Ver arriba |
| `companyScope() -> CompanyScope?`, `scoped(_ predicate:)`, `fetch(_:_:sortBy:limit:)`, `count(_:_:)`, `insert(_:)` | Para filtrar e insertar desde la UI |

Error nuevo: `BookkeepingError.companyLimitReached(Int)` (con su texto).

### Cómo debe filtrar la UI (agente de «varias empresas en pantalla»)

Hoy hay ~167 `@Query` y ~77 `FetchDescriptor` sin filtrar en `ChirograUI`. Cada uno debe limitarse a la empresa activa.
El filtro lo da `CompanyScope.predicate(_:)` (= `Modelo.ownedBy(id, includeOrphans:)`), que ya incluye los huérfanos
cuando la activa es la principal:

```swift
// 1) Lista con @Query: la vista recibe el ámbito (de un entorno o del padre) y monta su Query en el init.
struct InvoiceList: View {
    @Query private var invoices: [Invoice]

    init(scope: CompanyScope) {
        _invoices = Query(filter: scope.predicate(Invoice.self), sort: \Invoice.issueDate, order: .reverse)
    }
}

// 2) Con otra condición: componer predicados (SwiftData admite `evaluate` dentro de #Predicate).
init(scope: CompanyScope) {
    let owned = scope.predicate(Bill.self)
    let open = BillStatus.open.rawValue
    _bills = Query(filter: #Predicate<Bill> { owned.evaluate($0) && $0.statusRaw == open })
}

// 3) A mano, sin componer (equivalente):
let id: UUID? = scope.id
let orphans = scope.includeOrphans
_customers = Query(filter: #Predicate<Customer> { ($0.companyID == id || (orphans && $0.companyID == nil)) && !$0.isArchived },
                   sort: \Customer.name)

// 4) FetchDescriptor en una acción: mejor por Bookkeeper, que ya filtra.
let books = Bookkeeper(context: context)
let drafts = try books.fetch(Invoice.self, #Predicate { $0.statusRaw == "draft" })
let descriptor = FetchDescriptor(predicate: try books.scoped(#Predicate<Expense> { $0.voidedAt == nil }))
```

Para que las listas cambien al cambiar de empresa, el ámbito debe ser parte de la identidad de la vista (p. ej.
`.id(scope.id)` en la raíz, o leer `@AppStorage(ActiveCompany.defaultsKey)` y recalcular `Bookkeeper(context:).companyScope()`).
`Company` no tiene `companyID`: la empresa activa se busca por `id`. Lo que la UI inserte directamente debe pasar por
`books.insert(modelo)` (o poner `companyID` a mano); si no, queda huérfano hasta el próximo guardado de `Bookkeeper` o
`adoptOrphanRecords()`. `SampleData.isSample` sigue significando «todas las empresas son de ejemplo».

## 2. Copias `.chirogra` por empresa · `Backup.swift`

| Servicio | Qué hace |
|---|---|
| `BackupArchive.make(from:appVersion:now:)` | Copia de la **empresa activa** (sus registros y, si es la principal, los huérfanos) |
| `BackupArchive.make(from:companyID:appVersion:now:)` | Copia de una empresa concreta (`nil` = todo) |
| `BackupArchive.info(of:)` | Como antes; `Info.companyID` nuevo (`nil` en copias viejas) |
| `BackupArchive.restore(_:into:actor:) -> Info` | Como antes para la UI actual: **sustituye la empresa activa** (las demás no se tocan) |
| `BackupArchive.restoreCompany(_:into:mode:actor:) -> RestoreResult` | `mode: .replaceCompany(id)` (`nil` = la activa) o `.newCompany` (dentro del límite). Deja activa la restaurada (`RestoreResult.companyID`) |

Las copias de antes (esquema ≤ 3, sin `companyID`) se restauran: todo pasa a la empresa de la copia (si traía varias
empresas, de libros mezclados, la más antigua; las demás no se restauran). Si algún id de la copia ya existe en otra
empresa (restaurar como nueva la copia de una empresa que sigue aquí), se dan ids nuevos a todo conservando las
referencias (`RestoreResult.renumbered`). Restaurar ya no comprueba solo lectura (como antes: es la vía para recuperar
los libros). `eraseAll(in:)` sigue borrando **todo** (lo usa «Empezar con mi empresa» con los datos de ejemplo).
`scripts/gen-backup.py` lee ahora los modelos de `SchemaV4*.swift` y exporta por `BackupScope`.

## 3. Banca y conciliación · `ChirograCore/BankStatement.swift`, `Bookkeeper+Banking.swift`, `Bookkeeper+Reconciliation.swift`

**Signo de los importes** (`BankTransaction.amount`, `BankStatementLine.amount`): el efecto en la cuenta contable como
debe − haber. Banco: positivo = depósito, negativo = cargo. Tarjeta: negativo = compra, positivo = pago o devolución.

### Fuentes (`ChirograCore`)
- `protocol BankTransactionSource { var kind: BankSourceKind; func statementLines() async throws -> [BankStatementLine] }`.
  Plaid será otra implementación; nada más cambia.
- `CSVBankSource(text:/data:, settings: CSVImportSettings)` con `parse()`. `CSVImportSettings(mapping: CSVColumnMapping,
  dateFormat:, amountSign: .signed/.inverted, delimiter:, hasHeaderRow:)`. `CSVColumnMapping(date:, details:, amount:)`
  o con `debit:`/`credit:` (cargos y abonos), y opcionales `payee`, `memo`, `reference` (id del banco), `checkNumber`.
  `CSVImportSettings.suggested(for: text)` propone columnas, formato de fecha y delimitador por la cabecera (en inglés o
  español) para que el usuario solo confirme. Importes como «$1,234.56», «(12.00)», «12.00-», «CR/DR».
- `OFXBankSource(text:/data:)` con `parse() -> OFXStatement` (OFX 1.x SGML y 2.x XML, QFX igual): un movimiento por
  `STMTTRN` con `FITID`; además `ledgerBalance`/`balanceDate` (para proponer el saldo de la conciliación),
  `accountLast4` (para proponer la cuenta) e `isCreditCard`.
- `externalID`: `fitid:…`, `ref:…` (columna de referencia) o, sin id, `h:…` = hash estable de fecha, importe,
  descripción y número de repetición en el archivo (`BankStatementLine.stableID`). Errores: `BankStatementError`
  (`unreadableRow(n)`, `empty`, `missingColumn`, `notOFX`) — **sin texto todavía**: la UI pone el mensaje.

### Importar, bandeja y reglas
| Servicio | Qué hace |
|---|---|
| `importTransactions(from: source, into: account, applyRules:) async -> BankImportResult` | Lee la fuente e importa |
| `importStatementLines(_:source:into:applyRules:) -> BankImportResult` | Guarda «por revisar» lo que no estaba (mismo `externalID` en la cuenta, también si se ignoró = repetido) y aplica las reglas. Resultado: `imported`, `duplicates`, `autoApplied`, `failures`, `batchID` |
| `saveImportProfile(_ settings:name:for:into:)`, `importProfiles(for:)`, `BankImportProfile.settings` | Perfil de columnas del CSV por cuenta |
| `bankTransactions(account:status:)`, `bankInbox(account:)`, `bankTransaction(id:)` | Listas (más reciente primero) |
| `bankRules(includeInactive:)`, `saveBankRule(_ BankRuleInput, into:)`, `deleteBankRule(_:)` | Reglas, por prioridad (mayor primero) |
| `rule(matching:among:)`, `applyBankRules(to:) -> BankRuleRun` | La primera regla activa que encaja (texto sin mayúsculas ni acentos en descripción o beneficiario, signo, cuenta) propone `categoryAccountID`/`vendorID`/`payee`; con `autoApply` además registra. Si registrar falla (periodo cerrado…), queda por revisar con la propuesta |

### Coincidencias y registrar desde el movimiento
| Servicio | Qué hace |
|---|---|
| `matchCandidates(for:toleranceDays: 5) -> [BankMatchCandidate]` | Líneas del diario de esa cuenta con el mismo importe, a ±5 días, sin conciliar ni emparejar, sin asientos revertidos; las más cercanas primero (`line`, `entry`, `daysApart`) |
| `match(_:to: line)` | Empareja con lo ya registrado → `matched` |
| `categorize(_:as:vendor:customer:payee:memo:) -> BankCategorization` | Registra con la cuenta elegida (o la de la regla): cuenta de dinero → **transferencia** (`EntrySource.transfer`); salida → **gasto** pagado con la cuenta del movimiento; entrada → **depósito** (`EntrySource.bankDeposit`: ingreso sin factura, aportación, devolución). Un guardado → `categorized` |
| `recordPayment(from:for: invoice)` | La entrada como cobro de una factura (no más que su saldo) |
| `payBill(from:bill:)` | La salida como pago de una factura de proveedor |
| `ignore(_:)`, `returnToInbox(_:)` | Ignorar / devolver a la bandeja (el documento creado, si lo hay, se queda) |

### Sesión de conciliación (DISEÑO §4.6)
| Servicio | Qué hace |
|---|---|
| `startReconciliation(for:statementDate:endingBalance:beginningBalance:)` | Una abierta por cuenta; saldo inicial = final de la última terminada (o el dado / 0 la primera vez) |
| `reconciliationLines(_:)`, `suggestedClearedLines(_:)` | Líneas marcables hasta la fecha del extracto; las emparejadas con el banco se proponen marcadas |
| `setCleared(_ lines:_ cleared:in:)`, `summary(of:) -> ReconciliationSummary` | Marcar; `clearedIncreases`, `clearedDecreases`, `clearedBalance`, `difference`, `isBalanced` (saldos en el lado normal: en tarjetas, lo que se debe) |
| `completeReconciliation(_:)` | Solo con diferencia 0 |
| `updateReconciliation`, `reopenReconciliation` (solo la última), `cancelReconciliation` | |
| `reconciliations(for:)`, `openReconciliation(for:)`, `lastCompletedReconciliation(for:)` | |
| `hasReconciledLines(_ entry)`, `isReconciled(_ line)` | Para avisar en la UI |

**Lo conciliado no se cambia sin aviso:** `reverse` (y con él anular y editar gastos y facturas) falla con
`BookkeepingError.reconciledLines` si el asiento tiene líneas de una conciliación **terminada**. La UI muestra el aviso y,
si el usuario confirma, repite con `books.allowingReconciledChanges()` (queda en la auditoría).

## 4. Reportes · `Bookkeeper+Reports.swift`, `ChirograCore/CashFlow.swift`

- `AccountingBasis` (`.accrual`, `.cash`). `ledgerLines(basis:)`, `incomeStatement(from:to:basis:)`,
  `balanceSheet(asOf:basis:)`, `trialBalance(asOf:basis:)`.
- **Base caja** (`cashBasisLedgerLines()`): las líneas del diario vistas en caja, balanceadas asiento por asiento (sirven
  todos los `ReportBuilder`). Fuera los asientos de facturas, notas de crédito y facturas de proveedor (con sus
  reversiones); en cada cobro, la línea de CxC se sustituye por las líneas de la factura (ingresos, sales tax, descuento)
  en proporción a lo cobrado sobre lo que se debía (total − notas de crédito de esa factura), exacto al centavo
  (`ReportBuilder.allocateSigned`); igual con los pagos a proveedores (CxP → líneas de gasto) y los reembolsos de saldo
  a favor (CxC → líneas de las notas reembolsadas). Aproximación: una nota aplicada a **otra** factura no cambia el reparto.
- **Flujo de efectivo** indirecto: `cashFlowStatement(from:to:) -> CashFlowStatement` (`netIncome`,
  `nonCashAdjustments` —depreciación: líneas de activo fijo en asientos sin efectivo y con gasto—, `workingCapital`,
  `investing`, `financing`, `beginningCash`, `endingCash`, totales, `isReconciled`). Secciones por tipo de detalle
  (`CashFlowSection`): efectivo = caja, bancos, fondos no depositados; tarjetas y sales tax en operación; saldos de
  apertura en financiamiento. `LedgerLine` gana `entryID` (opcional) para esto.
- **Paquete para el contador**: `accountantPackage(from:to:basis:) -> AccountantPackage` con `incomeStatement`,
  `balanceSheet`, `trialBalance`, `cashFlow`, `taxSummary` y `files` (CSV: estado de resultados, balance, balanza, flujo
  de efectivo, diario y deducibles). La UI de exportar (carpeta, ZIP o compartir; PDF) la hace otro agente.
- CSV nuevos en `ChirograCore`: `CSVExport.journal`, `.cashFlow`, `.taxSummary`, `.budget`; `journalExportRows(from:to:)`.

## 5. Presupuestos · `Bookkeeper+Budgets.swift`, `ChirograCore/BudgetReport.swift`

| Servicio | Qué hace |
|---|---|
| `budgets()` | Del año más reciente al más antiguo |
| `createBudget(name:fiscalYear:copying:factorPercent:)` | Vacío o copia de otro (×%) |
| `createBudget(name:fiscalYear:fromActualsOf:factorPercent:)` | Con lo real de un año fiscal |
| `setBudgetAmount(_:account:month:in:)`, `setBudgetAmounts(_ 12 importes en orden fiscal:account:in:)`, `setAnnualBudget(_:account:in:)` | Importes (0 quita la línea; anual repartido a partes iguales) |
| `renameBudget`, `deleteBudget` | |
| `months(ofFiscalYear:) -> [BudgetMonth]` | Los 12 meses (con el mes de inicio de la empresa) |
| `budgetVsActual(_:grouping: .month/.quarter/.year, basis:) -> BudgetReport` | Filas de ingresos, gastos y otras, por periodo: `budget`, `actual`, `variance`, `isFavorable`, `percentOfBudget`; `budgetedNetIncome`, `actualNetIncome` |

`fiscalYear` = año natural en que **empieza** el año fiscal; `month` = mes natural. Importes en el lado normal de la cuenta.

## 6. Deducibles · `ChirograCore/TaxForms.swift`, `TaxMapping.swift`

- Catálogo `TaxFormCatalog.lines(for: .scheduleC / .form1120S, year:)` con número, nombre oficial (inglés) y en español,
  tipo (ingreso/deducción), parte, `rollsUpTo` (parte III → línea 4; «20-meals» → 20) y `deductiblePercent` (comidas
  50 %). Ids `"scheduleC:22"`. 2026 usa el de 2025 hasta que salga el formulario definitivo.
- `TaxForm.forEntity(_:)`: dueño único y LLC → Schedule C; S corp → 1120-S; sociedad y C corp → `nil` (sin formulario).
- Por defecto, la línea sale del código de la cuenta en las plantillas (`TaxFormCatalog.defaultLineNumber`) y, en
  cuentas propias, del tipo de detalle. `Account.taxFormLineRaw`: vacío = sugerida; `TaxFormCatalog.none` = excluida.
- `taxForm()`, `taxLine(for:form:year:)`, `setTaxLine(_ id:for:)` (`nil` = volver a la sugerida),
  `taxSummary(from:to:basis:form:year:) -> TaxFormSummary` (`rows` con `amount`, `deductibleAmount` y cuentas;
  `total(of: "4")`, `totalIncome`, `totalDeductions`, `excluded`).

## 7. Sales tax por código postal y enlace de pago · `PostalSalesTax.swift`

- Tabla: `PostalTaxTable(json:)` / `PostalTaxTable(rates:)` con `PostalTaxRate` (`postalCode`, `state`, `region`,
  `stateRateMillionths`, `localRateMillionths`). Formato JSON en el código. **Aún sin fuente**: la app la cargará en
  `PostalTaxTables.current` cuando se decida (PLAN-FASE2 §7).
- `suggestedSalesTax(for: customer, table:) -> SalesTaxSuggestion?`: con origen, el ZIP del negocio (salvo cliente de otro
  estado); con destino, el del cliente. Trae `existingTaxCodeID` si ya hay un impuesto con esa tasa total.
  `createTaxCode(for:)` crea la tasa estatal + la local en un grupo «Austin, TX» (no cambia el predeterminado). Solo
  sugiere: el usuario confirma.
- Enlace: `setPaymentSettings(link:instructions:showPayNow:)` (valida http/https) y `paymentLink(for: invoice) -> URL?`
  (sustituye `{amount}`, `{number}`, `{customer}`; `nil` sin enlace, sin «Pagar ahora» o sin saldo). `PaymentLinkTemplate.url`.

## 8. Migración

- `ChirograMigrationPlan`: `[SchemaV1, SchemaV2, SchemaV3, SchemaV4]`; etapas `migrateV1toV2` (ligera),
  `migrateV2toV3` (a medida, `entityName` → `subjectEntity`) y **`migrateV3toV4` (a medida)**: Core Data añade lo nuevo
  y `didMigrate` llama a `CompanyOwnership.adoptOrphans(in:archivingExtraCompanies: true)`, que pone a todo la empresa
  principal (la más antigua por fecha de alta y después id: determinista, así dos aparatos que migran a la vez escriben
  lo mismo) y numera `sortOrder`.
- **Libros mezclados** (dos altas que se juntaron por iCloud antes del arreglo del 7-nov): no se pueden separar, así que
  todo pasa a la más antigua y las demás —sin nada propio— quedan **archivadas** (no cuentan para el límite y se pueden
  borrar).
- Toda la migración toca cada registro (`companyID`), así que con iCloud se vuelve a subir todo una vez.
- Pruebas: `MigrationTests` (V1→V4, V2→V4 con `subjectEntity`, V3→V4 con dos empresas, plan); `FrozenSchemaTests`
  (hashes de V1, V2 y V3 = los publicados); y, a mano, un almacén escrito por `c214680` (1.0.1, esquema 3, con
  `SampleData`, recibo y nota de crédito) migró y cuadró:
  `CHIROGRA_STORE=/ruta/Chirogra.store swift test --filter MigrationTests` (copia el almacén antes de abrirlo).

## 9. Pruebas

`swift test` en `Packages/ChirograKit`: **238 pruebas** (antes 197). Nuevas: `CompaniesTests`, `BankingTests`,
`PhaseTwoReportsTests`, `FrozenSchemaTests` (datos); `BankStatementTests`, `CashFlowAndBudgetTests` (núcleo); y más en
`MigrationTests`, `CloudKitSchemaTests` y `BackupTests` (la copia cubre los modelos nuevos). La app compila para iOS y macOS.

## 10. Pendiente y decisiones abiertas

- **UI** (otros agentes): filtrar las `@Query`/`FetchDescriptor` (§1), selector y lista de empresas, alta de otra
  empresa, límite por plan (el producto de contadores pone `Bookkeeper.companyLimit = CompanyLimits.accountant`),
  bandeja del banco, conciliación, presupuestos, reportes nuevos, exportar para el contador, «Pagar ahora» y QR,
  ZIP en empresa y clientes. Llamar a `adoptOrphanRecords()` al abrir y tras sincronizar.
- **Tabla de sales tax por ZIP**: fuente y licencia por decidir; luego cargarla en `PostalTaxTables.current`.
- **Schedule C / 1120-S 2026**: revisar el catálogo cuando el IRS publique los formularios definitivos.
- **Sociedades (1065) y C corp (1120)**: sin formulario en Chirogra (`TaxForm.forEntity` → `nil`).
- **Archivar cuenta para el límite**: las archivadas no cuentan; con el plan normal se puede archivar una y crear otra
  (los libros archivados siguen en iCloud). Decidir si se quiere así.
- **Base caja**: aproximación con notas de crédito aplicadas a otra factura (§4).
- **Plaid** (fase 3): implementar `BankTransactionSource` con `kind = .plaid`.
- Antes de publicar: desplegar el esquema 4 a Producción y probarlo allí (CONTEXTO).
