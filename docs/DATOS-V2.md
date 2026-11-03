# Datos v2: esquema 2.0.0 y servicios nuevos

Capa de datos y lógica para lo que el canvas dibuja y la app aún no tenía (2-nov-2026). Las pantallas **no** cambiaron: este documento es para los agentes de pantallas, que no deben tocar el modelo. Todo vive en `Packages/ChirograKit/Sources/ChirograData` (servicios en `Bookkeeper+*.swift`) y `ChirograCore` (impuesto incluido).

Reglas que siguen valiendo: las vistas no escriben asientos; todo cambio contable pasa por `Bookkeeper`. Los asientos contabilizados son inmutables: editar = revertir + asiento nuevo.

## 0. Esquema y migración

- `SchemaV2` (2.0.0) en `SchemaV2.swift` + `SchemaV2Models.swift`. Los `typealias` (`Company`, `Invoice`…) ahora apuntan a `SchemaV2.X`; las pantallas siguen usando los mismos nombres.
- `SchemaV1.swift` queda **congelado** (solo propiedades guardadas). No tocarlo nunca.
- `ChirograMigrationPlan`: `[SchemaV1, SchemaV2]`, una etapa `.lightweight`. Solo cambios aditivos: propiedades nuevas con valor por defecto u opcionales, 8 modelos nuevos con relaciones opcionales con inversa, sin `.unique`, sin `.deny`.
- `ChirograStore.makeContainer(inMemory:cloudKitContainer:url:)`: `url` nuevo, para pruebas.
- Probado: un almacén V1 creado en la prueba (`MigrationTests`) y uno escrito por la app publicada (`4f4e68e`, con `SampleData`, nota de crédito y recibo) se abren, migran y cuadran. Para repetir lo segundo: `CHIROGRA_V1_STORE=/ruta/Chirogra.store swift test --filter MigrationTests` (copia el almacén antes de abrirlo).
- **Para un esquema 3:** copiar los modelos de `SchemaV2` tal cual a un `SchemaV2` congelado (como se hizo con V1), crear `SchemaV3` y añadir la etapa.

## 1. Pagos programados y en lote (Por pagar) · `Bookkeeper+Payables.swift`

**Modelo `Bill` (nuevo):** `scheduledPaymentDate: Date?`, `scheduledPaymentAccountID: UUID?`, `scheduledPaymentMethodRaw` (`scheduledPaymentMethod: PaymentMethod?`), `autoPay: Bool` (cargo automático, lo pone una plantilla recurrente), `recurringTemplateID`, `recurrenceDate`. Calculadas: `isScheduled`.

| Servicio | Qué hace |
|---|---|
| `schedulePayment(for:on:from:method:)` | Programa el pago (cuenta de banco/caja/tarjeta). Sin asiento. |
| `unschedulePayment(for:)` | Quita la programación (y el cargo automático). |
| `payBills(_:on:from:method:reference:) -> [BillPayment]` | **Pago en lote**: un pago y un asiento por factura, saldo completo, misma fecha/cuenta/método. Todo o nada. |
| `scheduledBills(dueOnOrBefore:)` | Abiertas con pago programado hasta esa fecha. |
| `payScheduledBills(dueOnOrBefore:onlyAutoPay:) -> ScheduledPaymentRun` | Registra los programados que vencen hoy o antes, cada uno con **su** fecha programada; los que fallan quedan en `failures` y siguen programados. |
| `runAutomations(asOf:) -> AutomationRun` | Recurrentes hasta hoy + pagos de cargo automático. Idempotente. |
| `pay(_:amount:date:from:method:reference:save:)` | El de siempre, con `reference` y `save` nuevos (por defecto igual que antes). Al saldar la factura borra su programación. |
| `void(_ bill:)` | Anula una factura de proveedor sin pagos (revierte su asiento en su fecha). |

**Pantallas:** `MacPorPagar` (casillas + «Pagar $X» → `payBills`; chip «Programadas» → `isScheduled`; tarjeta «Pagos programados»; estado «Programada · 7 nov», «Recurrente · cargo automático» = `autoPay`), `ProveedorFicha` («Fecha de pago» + «Programar» → `schedulePayment`), Inicio (próximos pagos: `scheduledPaymentDate`). **La app debe llamar a `runAutomations()` al abrirse y al volver al primer plano** (Shell/RootView) y, si `autoPayments.failures` no está vacío, avisar.

## 2. Recurrentes · `Bookkeeper+Recurring.swift`

**Modelo `RecurringTemplate`:** `name`, `kind` (`.expense` / `.bill`), `vendor`, `payee`, `memo`, `lines: [RecurringTemplateLine]` (`details`, `amount`, `accountID`), `paymentAccountID`, `method`, `frequency` (`.weekly/.monthly/.quarterly/.annual`), `startDate`, `nextDate`, `endDate?`, `isActive`, `autoCharge`, `billTermsDays`, `lastGeneratedDate`, `lastRunAt`. Calculadas: `total`, `sortedLines`, `isFinished`, `occurrence(after:)`. Las fechas se anclan al inicio (31 ene → 28 feb → 31 mar).

Qué genera cada repetición:
- **Gasto** con cargo automático: `Expense` contabilizado. Sin cargo automático: `Expense` **sin asiento** («por confirmar»; se confirma con `record(expense)`).
- **Factura por pagar**: `Bill` registrada (vence a `billTermsDays`). Con cargo automático, además su pago queda programado al vencimiento con `autoPay = true`.
- Lo generado guarda `recurringTemplateID` y `recurrenceDate`.

| Servicio | Qué hace |
|---|---|
| `saveRecurringTemplate(_ RecurringTemplateInput, into:)` | Alta/edición. Si cambia inicio o frecuencia, recalcula `nextDate` desde la última generada. |
| `setRecurringTemplate(_:active:asOf:)` | Pausar/reanudar (al reanudar no genera lo que pasó en pausa). |
| `deleteRecurringTemplate(_:)` | Borra la plantilla; lo generado se queda. |
| `recurringTemplates(includePaused:)` | Lista por próxima fecha. |
| `generateRecurring(through:) -> RecurringRun` | Genera hasta la fecha. **Idempotente**: busca `recurringTemplateID` + `recurrenceDate` antes de crear; dos llamadas o dos aparatos que ya sincronizaron no duplican. Si una repetición falla (periodo cerrado…) la plantilla no avanza y va a `failures`. |
| `resolveRecurringDuplicates() -> Int` | Si dos aparatos **sin conexión** generaron la misma repetición: conserva la más antigua y anula las demás (gasto: reversión; factura sin pagos: anulación). Llamarlo tras sincronizar. |

**Pantallas:** `MacGastoNuevo` («Repetición», «Gasto recurrente», «Cada mes, el día 29 · sin fecha de fin» → `RecurringTemplateInput`; guardar el gasto y además `saveRecurringTemplate` con `startDate` = siguiente repetición, o guardar solo la plantilla y dejar que genere), lista de recurrentes en Gastos/Por pagar, Inicio («Recurrente» en próximos pagos). **Las listas de gastos deben distinguir los que no tienen asiento** (`!expense.isPosted`: «Por confirmar» + botón Registrar) **y los anulados** (`expense.isVoid`: ocultos o tachados; no cuentan).

## 3. Editar lo ya contabilizado · `Bookkeeper+Editing.swift`

### Gasto
- `ExpenseInput` (nuevo, en `DocumentInputs.swift`): `date`, `payee`, `vendor`, `customer`, `paymentAccountID`, `method`, `reference`, `memo`, `salesTaxIncluded`, `lines: [ExpenseInput.Line]` (`details`, `amount`, `accountID`). `ExpenseInput(expense)` precarga el editor.
- `createExpense(_:post:) -> Expense` — alta (con o sin asiento).
- `updateExpense(_:with:) -> JournalEntry?`:
  - sin asiento: reescribe y listo;
  - con asiento y cambios contables (fecha, cuenta de pago, líneas, proveedor o cliente): **reversión del original en su misma fecha + asiento nuevo**, enlazados (`JournalEntry.replacesEntryID` / `replacedByEntryID`), `expense.journalEntryID` apunta al vigente, `expense.revision += 1`, `AuditEvent` «edit». Sigue siendo el mismo `Expense`;
  - solo texto (beneficiario, nota, referencia, método, impuesto incluido): sin asientos.
  - En periodo cerrado falla con `.invalidEntry(.periodLocked)`: pedir la contraseña y usar `unlockedForClosedPeriod(password:)` (§12).
- `void(_ expense:reason:on:)` — anula (revierte el asiento vigente) y pone `voidedAt`.
- `entries(ofExpense:)` — historial de asientos del gasto (para «Historial» en el inspector).
- `record(_ expense:save:)` — el de siempre; también pone `customerID` en las líneas.

### Cuenta del plan
- `AccountInput` (`code`, `name`, `subtype`, `details`, `parentID`, `last4`); `AccountInput(account)` precarga.
- `updateAccount(_:with:)`: nombre obligatorio; número único entre activas (`BookkeepingError.duplicateAccountCode`); tipo de detalle dentro del mismo tipo siempre (salvo cuentas de sistema); **cambiar de tipo solo sin movimientos ni subcuentas**; cuenta principal del mismo tipo, activa, sin movimientos propios y sin ciclos; últimos 4 vacío o 4 dígitos.

### Tasa de impuesto
- `updateTaxRate(_:name:agency:rateMillionths:)` (0…1 000 000 = 0–100 %). Las facturas emitidas guardan su impuesto en `taxLines` y **no cambian**; las notas de crédito y el resumen de sales tax usan ahora las tasas guardadas (`issuedTaxComponents(of:)`). Los borradores toman la tasa nueva al emitirse.

### Impuesto predeterminado de la empresa
- `Company.defaultTaxGroupID`: id de un `TaxGroup` **o** de una `TaxRate` (una tasa sola cuenta como grupo de un componente en `taxComponents(groupID:on:)`, así que `Invoice.taxGroupID` también puede llevar el id de una tasa).
- `setDefaultTax(_ id:)`, `taxCodeName(_ id:)`.
- `newInvoiceDefaults(for:issueDate:) -> NewInvoiceDefaults` (`taxGroupID` del cliente o de la empresa, `nil` si el cliente está exento; `dueDate` por condiciones del cliente o `Company.defaultPaymentTermsDays`; `customerMessage` = `Company.defaultInvoiceMessage`; `pricesIncludeTax`). **El editor de factura y el de estimado deben precargar con esto.**

**Pantallas:** `MacGastos`/detalle de gasto («Editar» en gastos registrados), `MacPlanCuentas` («Editar…»), `MacImpuestos` («Editar tasa…», «· Predeterminada»), `Impuestos` («Ventas Austin es la tasa predeterminada»), Ajustes.

## 4. Impuesto

- `Company.pricesIncludeTax` («Precios con impuesto incluido»). Cada factura copia el valor al crearse (`Invoice.pricesIncludeTax`; `InvoiceDraftInput.pricesIncludeTax: Bool?` lo fuerza). Con el ajuste: `subtotal` = líneas con impuesto, **`total = subtotal − discount`**, `taxTotal` es el impuesto separado, `netSales` = ventas sin impuesto. Cálculo en `SalesTaxCalculator.taxesIncluded(inGross:components:)`: base = bruto / (1 + tasa) al centavo, impuesto = bruto − base (cuadra siempre), desglose por componente con el residuo en la tasa mayor. `PostingRules.invoice(…, pricesIncludeTax:)`.
- Las **notas de crédito** siguen siendo con impuesto aparte (`amount` sin impuesto) también sobre facturas con impuesto incluido.
- `Company.salesTaxSourcing` (`.origin` / `.destination`): informativo.
- `Expense.salesTaxIncluded` (centavos): sales tax pagado dentro del total; informativo, no cambia el asiento (en EE. UU. es parte del gasto). `expense.subtotalBeforeTax`.
- `totals(for: Invoice)` / `totals(for: Estimate) -> DocumentTotals` — totales de un borrador o estimado con las reglas de emisión (para vistas previas).

**Pantallas (Ventas, importante):** `InvoicePDF.swift` (línea ~155) e `InvoiceDetailView.swift` (~462) muestran Subtotal + Impuesto = Total. Con `invoice.pricesIncludeTax` eso no suma: mostrar «Total (impuesto incluido)» y el impuesto como «Incluye $X de impuesto», o Subtotal = `invoice.netSales`. El editor de factura debe calcular la vista previa con `books.totals(for:)` en vez de sumar a mano. `MacGastoNuevo` «Impuesto incluido» → `salesTaxIncluded`. Ajustes/Impuestos: interruptor «Precios con impuesto incluido» y origen/destino.

## 5. Gasto facturable
`Expense.customer: Customer?` (inversa `Customer.billableExpenses`), `isBillable`. Lo escribe `ExpenseInput.customer`. **Pantallas:** `MacGastoNuevo` «Cliente o proyecto (opcional)», ficha de cliente (gastos por refacturar).

## 6. Proveedor
`Vendor.w9Received`, `w9ReceivedDate`, `w9Attachment: Attachment?`, `preferredPaymentMethod: PaymentMethod?` (raw vacío = sin preferencia), `preferredPaymentAccountID`. Servicios: `setW9(for:received:on:)`, `attachW9(_:filename:contentType:to:receivedOn:)` (foto→JPEG, PDF tal cual), `setPreferredPayment(for:method:account:)`. `payScheduledBills` usa la cuenta preferida si la factura no tiene cuenta programada. **Pantallas:** `MacProveedorFicha` (inspector «Formulario W-9 · Recibido», «Pago preferido · Zelle · Corriente ••4821»), `ProveedorFicha`.

## 7. Cuenta bancaria / tarjeta
`Account.last4` («4821»), `account.maskedName` → «Corriente ••4821». Se edita con `updateAccount`. **Pantallas:** todas las que nombran cuentas de pago (Banca, Inicio, gastos, pagos).

## 8. Clientes
`Customer.contactName`, `contactTitle`, `contactLine` («Laura Méndez · Gerente»), `taxID` («ID fiscal»). Notas fechadas: modelo `CustomerNote` (`date`, `text`, `author`, `customer`), `customer.sortedNotes` (recientes primero). Servicios: `addNote(to:text:date:)` (autor = `actor` del `Bookkeeper`), `updateNote(_:text:date:)`, `deleteNote(_:)`. `Customer.notes` sigue siendo la nota fija. **Pantallas:** `ClienteFicha` (pestañas Contacto y Notas, «Nueva nota»), `MacClienteFicha` (Contacto · Persona, Notas).

## 9. Envíos y recordatorios de facturas
Modelo `InvoiceEvent` (`kind`: `.sent` / `.reminder`, `date`, `recipient`, `subject`, `message`, `invoice`); `invoice.sortedEvents`, `lastSentDate`, `lastReminderDate`. Servicios: `recordInvoiceSent(_:to:subject:message:date:)` (factura emitida) y `recordReminder(…)` (solo pendientes). La app no manda correos: abre el redactor del sistema y al volver registra el evento. **Pantallas:** `FacturaEnviar` (Para/Asunto), `FacturaDetalle` y `MacInicio` («Actividad»: creada, enviada, recordatorio; «vista por el cliente» es fase 2), `MacClienteFicha` («Enviar recordatorio» → «Recordatorio enviado» si `lastReminderDate` es hoy).

## 10. Plantilla de factura (`Company`)
`logo: Attachment?` (`setCompanyLogo(_:filename:contentType:)` → PNG de 512 px máx., `removeCompanyLogo()`), `invoiceAccentHex` (presets `InvoiceAccent`: `.ink` Tinta, `.graphite` Grafito, `.copper` Cobre, `.petroleum` Petróleo, `.forest` Bosque, con `hex` y `softHex`; `company.invoiceAccent` si coincide), `invoiceStyle` (`.classic` / `.compact`), `invoiceShowLogo`, `invoiceShowEIN`, `invoiceShowAddress`, `invoiceShowPhone`, `defaultInvoiceMessage`, `invoiceFooter` (pie/términos), `defaultPaymentTermsDays` («Términos predeterminados»), `website`.

**Qué debe cambiar el agente de Ventas en `ChirograUI/Sales/InvoicePDF.swift` (`InvoiceDocumentView`):** ya recibe `company`; leer de ahí el logo (`company.logo?.data`, si `invoiceShowLogo`), el color (`invoiceAccentHex`, y `InvoiceAccent(hex:)?.softHex` para la cabecera de tabla), el estilo (clásico = «FACTURA» espaciado; compacto = «Factura», filas más juntas), EIN/dirección/teléfono según los interruptores, y `invoiceFooter` al pie junto al mensaje de la factura. Además lo de §4 (impuesto incluido). Pantallas: `AjustesPlantilla`, `MacAjustes` (pestaña Plantilla).

## 11. Estimados · `Bookkeeper+Sales.swift`
Modelo `Estimate` (`number` de la serie `E-0001`, `title`, `customer`, `issueDate`, `expirationDate` = válido hasta, `status`, `taxGroupID`, `discount`, `pricesIncludeTax`, `customerMessage`, `memo`, totales `subtotal/taxTotal/total`, `sentDate`, `acceptedDate`, `acceptedBy`, `convertedDate`, `lines: [EstimateLine]`) y `EstimateLine` (como `InvoiceLine` + `invoicedQuantity`, `remainingQuantity`). **Sin asiento contable.** Estados `EstimateStatus`: `.draft/.sent/.accepted/.declined/.expired/.converted`; `effectiveStatus(asOf:)` muestra vencido un enviado pasado de fecha. `DocumentKind.estimate` (serie nueva; las empresas viejas la crean sola con prefijo `E-`).

| Servicio | Qué hace |
|---|---|
| `saveEstimate(_ EstimateInput, into:)` | Alta/edición (número al crearlo; no se edita si ya tiene facturas). Calcula totales. |
| `setStatus(_:of:acceptedBy:date:)` | Enviado / aceptado (por quién) / rechazado / vencido. |
| `convertToInvoice(_:portion:issueDate:) -> Invoice` | Crea una **factura en borrador** (con líneas, impuesto, mensaje, `estimateID`, parte proporcional del descuento). `portion`: `.all`, `.percent(50)` (anticipo; cada línea al 50 %), `.lines([ids])`. Cuando no queda nada por facturar → `.converted`. |
| `invoices(for:)`, `estimates()`, `totals(for:)` | Consultas. |

**Pantallas:** `Estimado` (resumen, «Aceptado por Laura Méndez el 30 oct · válido hasta 30 nov», opciones «Todo el estimado / Anticipo del 50 % / Elegir líneas», «Factura F-1050 creada como borrador» → luego «Revisar y enviar»), lista de estimados en Ventas, `ClienteFicha` historial («Estimado E-0009 · aceptado»).

## 12. Cierre de periodo · `Bookkeeper+Closing.swift`
- Modelo `PeriodClose`: `isReopen`, `lockDate` (vigente tras la acción), `previousLockDate`, `date` (cuándo), `actor`, `device`, `note`.
- `closeBooks(through:note:device:)` (solo avanza), `reopenBooks(to:password:note:device:)` (retrocede o `nil`; pide la contraseña si hay), `closingHistory()`.
- Contraseña: `Company.closingPasswordHash` guarda solo `pbkdf2-sha256$iteraciones$sal$hash` (PBKDF2-HMAC-SHA256, 120 000 iteraciones, sal de 16 bytes). `setClosingPassword(_:current:)`, `removeClosingPassword(current:)`, `verifyClosingPassword(_:)`, `company.hasClosingPassword`.
- **Registrar en un periodo cerrado:** `let unlocked = try books.unlockedForClosedPeriod(password:)` devuelve otro `Bookkeeper` que ignora la fecha de cierre (si no hay contraseña basta con pedirlo; queda auditado). Error: `BookkeepingError.wrongClosingPassword`.
- **Pantallas:** `MacCierre` («Cerrar octubre 2026» → `closeBooks`; «Reabrir septiembre» → `reopenBooks`; «Contraseña de cierre»; «Historial de cierres» → `closingHistory()`; «Device» = nombre del aparato que pase la UI). Hoy `AccountingWideViews.swift` (~206–225) y `AccountingViews.swift` (~1059) escriben `company.lockDate` a mano: deben pasar a estos servicios para que quede historial. Cualquier editor que falle con `.periodLocked` puede ofrecer «Desbloquear con contraseña».

## 13. Avisos (campana) · `Bookkeeper+Notices.swift`
- `notices(asOf:) -> [Notice]`, calculados de los datos (no se guardan): `.scheduledPaymentDue` (pago programado de hoy o antes), `.overdueInvoice`, `.salesTaxDue` (fecha límite del periodo ya terminado en ≤ 15 días y saldo de la cuenta de la agencia > 0), `.billDueSoon` (vence en 0–7 días, sin programar), `.recurringGenerated` (repetición de los últimos 7 días; `needsConfirmation` si el gasto quedó sin asiento). Ordenados por urgencia.
- `Notice`: `id` (clave estable), `kind`, `date`, `days` (hasta `date`, negativo si pasó), `amount`, `party`, `reference`, `documentID`, `needsConfirmation`, `isRead`. **La UI pone el texto** (no hay cadenas en datos).
- Estado: modelo `NoticeState` (`key`, `isRead`, `isDismissed`). `markNoticeRead(_ id:)`, `markAllNoticesRead()`, `dismissNotice(_ id:)`, `unreadNoticeCount()`.
- Fechas de sales tax: `salesTaxFilingPeriod(for:containing:)` y `lastSalesTaxFilingPeriod(for:asOf:)` → `start`, `end`, `deadline` (día `Bookkeeper.salesTaxFilingDueDay` = 20 del mes siguiente). Sirve para «Fecha límite 20 ene 2027 · Faltan 80 días» en `MacImpuestos`/`Impuestos`.
- **Pantallas:** campana en la barra (Inicio iPhone/iPad/Mac) con globo `unreadNoticeCount`.

## 14. Datos de ejemplo
`SampleData` trae: últimos 4 en Corriente ••4821, Ahorro ••9032 y Tarjeta ••1177; impuesto predeterminado Austin, TX, mensaje y pie de factura; Hotel Mirador con contacto (Laura Méndez · Gerente) y 2 notas; envío registrado de cada factura y un recordatorio hoy de la vencida; B-221 con pago programado; Luis Mora (1099, W-9 recibido, pago preferido); recurrente «Adobe Creative Cloud» mensual con cargo automático (generó su gasto); gasto de Home Depot facturable a Café Aurora con impuesto incluido; estimado E-0001 aceptado sin facturar.

## 15. Errores nuevos
`BookkeepingError.wrongClosingPassword`, `.duplicateAccountCode(String)`; el resto usa `.invalidState(mensaje)` con textos ya traducidos en `App/Localizable.xcstrings`.

## 16. Riesgos conocidos
- **CloudKit:** antes de publicar, desplegar el esquema nuevo al entorno de producción de CloudKit (8 tipos de registro y campos nuevos). Un aparato con la versión vieja que edite un registro puede no conservar los campos nuevos (CloudKit guarda lo que manda cada versión): conviene actualizar todos los aparatos a la vez.
- Dos aparatos sin conexión pueden generar la misma repetición recurrente o cerrar el periodo a la vez: lo primero lo repara `resolveRecurringDuplicates()`; lo segundo deja dos entradas en el historial (inofensivo).
- `NoticeState` puede quedar duplicado por clave tras sincronizar; `notices()` toma el más reciente.
