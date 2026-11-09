# Fase 2 sin servidor: plan (7-nov-2026)

Lo que la fase 2 deja para hacer **sin servidor propio** (lo de Plaid, Stripe Connect y el sales tax exacto espera al
servidor). Fuente: DISEÑO §3.2 y §4.6, y las decisiones del usuario en CONTEXTO.md. Se construye sobre la 1.0.1
(esquema 3), que tiene que publicarse antes.

## Qué entra

| # | Función | Esquema | Notas |
|---|---|---|---|
| 1 | **Varias empresas** (plan para contadores, sin límite desde el 8-nov; antes hasta 5) | sí | Selector, lista con lo pendiente de cada una, «Añadir empresa», límite por plan |
| 2 | **Escanear recibos** | no | VisionKit + Vision + Foundation Models en el aparato; el usuario revisa antes de guardar |
| 3 | **Conciliación bancaria** | sí | Importar CSV/OFX, bandeja «Por revisar», reglas, coincidencias, sesión de conciliación |
| 4 | **Flujo de efectivo y base caja** | no | Se calculan de las líneas contabilizadas y de los cobros/pagos |
| 5 | **Deducibles + «Exportar para mi contador»** | sí | Cuenta → línea del Schedule C / 1120-S; paquete con reportes y CSV |
| 6 | **Presupuestos** | sí | Por cuenta y mes; real contra presupuesto |
| 7 | **Sales tax por código postal** (paso 1) | sí | Tabla publicada en chirogra.com; sugiere, el usuario confirma |
| 8 | **Enlace de pago propio** (cobro, paso 1) | sí | «Pagar ahora» y QR en el PDF y el correo de la factura |

## Reglas del esquema 4 (lo aprendido el 7-nov)

Todo lo que se despliega a Producción en CloudKit es **para siempre**:
- **Solo añadir**: propiedades nuevas con valor por defecto u opcionales, modelos nuevos con relaciones opcionales e inversas.
- **Nunca renombrar** (Core Data se niega con CloudKit: «Properties cannot be renamed…») **ni reutilizar** un nombre.
- **Ningún nombre reservado**: `entityName` (choca con `CD_entityName`), `description`, `moveReceipt`, `recordName`… (`CloudKitSchemaTests`).
- Las migraciones que mueven datos son **a medida** (`willMigrate`/`didMigrate`), como `migrateV2toV3`.
- Antes de publicar: `-qa.esquemaCloudKit 1` en el Mac, desplegar a Producción y **probar en Producción** con una compilación
  del equipo con `com.apple.developer.icloud-container-environment = Production` (CONTEXTO, 7-nov).

Un solo esquema 4 para todo lo de esta tabla (una migración, un despliegue).

## Esquema 4 (propuesta)

**Varias empresas**
- `companyID: UUID?` en todos los modelos salvo `Company` (y los hijos que solo existen dentro de su padre, si se decide
  filtrar por el padre). `migrateV3toV4` (a medida) lo rellena con la empresa actual.
- `Company.sortOrder: Int = 0`.

**Banca (DISEÑO §4.6)**
- `BankTransaction`: `companyID`, `accountID` (cuenta contable de banco o tarjeta), `date`, `amount` (Int64 con signo),
  `details`, `payee`, `externalID` (para no duplicar), `sourceRaw` (csv, ofx; plaid en el futuro), `statusRaw` (por revisar,
  categorizado, emparejado, ignorado), `matchedEntryID`, `createdDocumentID`, `importBatchID`, `importedAt`.
- `BankRule`: `companyID`, `name`, `matchText`, `amountSignRaw`, `targetAccountID`, `vendorID`, `autoApply`, `priority`.
- `BankImportProfile`: `companyID`, `accountID`, mapeo de columnas del CSV (texto JSON), formato de fecha, signo.
- `Reconciliation`: `companyID`, `accountID`, `statementDate`, `statementEndingBalance`, `beginningBalance`, `statusRaw`, `closedAt`.
- `JournalLine.reconciliationID: UUID?` y `JournalLine.clearedAt: Date?`.
- Fuentes desacopladas (`BankTransactionSource`): Plaid será una más sin tocar el resto.

**Presupuestos**: `Budget` (`companyID`, `name`, `fiscalYear`) con `lines` → `BudgetLine` (`accountID`, `month`, `amount`).

**Deducibles**: `Account.taxFormLineRaw: String = ""` (vacío = el sugerido por la plantilla del plan de cuentas).

**Sales tax y cobro**: `Company.postalCode`, `Customer.postalCode`, `Company.paymentLinkURL`, `Company.paymentInstructions`,
`Company.showPayNowOnInvoice: Bool = true`.

## Cómo se hace (equipo de agentes, CONTEXTO «Cómo se trabajó»)

1. **Datos** (un agente): `SchemaV4` + `migrateV3toV4` + servicios en `Bookkeeper` (empresa activa, importar CSV/OFX,
   reglas, coincidencias, conciliación, presupuestos, base caja, flujo de efectivo, mapeo de deducibles) + pruebas +
   `gen-backup.py` + `DATOS-V4.md`. La copia `.chirogra` pasa a ser **por empresa** (sirve para entregarle los libros al cliente).
2. **Varias empresas en pantalla** (un agente, solo): filtrar las ~167 `@Query` y ~77 búsquedas por la empresa activa,
   selector, lista de empresas, alta de otra empresa, límite por plan. Va solo porque toca casi todas las pantallas.
3. **En paralelo, por áreas**: (a) Banca y conciliación; (b) Reportes: flujo de efectivo, base caja, presupuestos,
   deducibles y exportar; (c) Recibos, enlace de pago y sales tax por código postal.
4. **Coordinador**: integración, `swift test`, capturas en simulador y en la copia del Mac, prueba en Producción,
   revisión del usuario en sus aparatos, y después `main`.

## Decisiones del usuario (7-nov)

- **Por partes:** 1.1 = varias empresas + plan para contadores + recibos + enlace de pago; 1.2 = conciliación bancaria;
  1.3 = flujo de efectivo, base caja, deducibles y presupuestos. El esquema 4 se hace de una vez para todo.
- **Precio del plan para contadores: después.** El producto se prepara con su identificador y el límite de empresas; el
  precio se pone en App Store Connect cuando el usuario lo decida.
- Formatos de extracto: CSV y OFX/QFX (CAMT.053 fuera salvo que lo pida).
- Pendiente: fuente y licencia de la tabla de sales tax por código postal (se investiga antes del punto 7).

## Después: con servidor (no entra en este plan)

Cuando se empiece el servidor propio (recomendado: Supabase, como Tamio, en un proyecto aparte; sin decidir):
- Conexión con el banco por **Plaid** (otra fuente de `BankTransactionSource`; plan «Chirogra + Banco»).
- Cobro con **Stripe Connect** (un enlace por factura; el cobro se registra solo).
- Sales tax exacto por dirección (Avalara, TaxJar, Stripe Tax…).
- Usuarios y permisos (el contador dentro de los libros del cliente).
- **Nómina (payroll): decidido el 8-nov, se empieza junto con el servidor.** Integrando un proveedor de nómina embebida
  (Gusto Embedded o Check), no desde cero: retenciones federales y estatales, depósitos, 941/940, W-2/W-4. Iría como plan más
  alto. Hoy se registra la nómina pagada con otro servicio como gasto o asiento (6850 Sueldos y salarios, 2300 Nómina por pagar).

