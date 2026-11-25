# Datos v6: esquema 6.0.0 (versión 1.4)

Rama `version-1.4` (25-nov-2026). La agenda (PLAN-1.4 §1) y el apartado para impuestos estimados (§3); canvas
https://claude.ai/artifact/GDQsZiSZRruwx3PhhLytyt.

## Esquema 6 (`SchemaV6.swift`)

Añade tres modelos, sin relaciones y con valor por defecto u opcional en todo: **`Appointment`**,
**`EstimatedTaxSetting`** y **`EstimatedTaxPayment`**. La migración 5 → 6 es ligera. Los demás modelos son los del 5 sin cambios; sus hashes quedan congelados en `FrozenSchemaTests.hashesV5`.

| Propiedad | Para qué |
|---|---|
| `customerID` | Cliente (`Customer.id`), opcional |
| `title`, `start`, `durationMinutes`, `location`, `notes` | Lo de la cita |
| `statusRaw` | `AppointmentStatus`: `scheduled`, `done`, `cancelled`, `noShow` y `removed` (una repetición borrada) |
| `reminderMinutes` | Aviso antes, en minutos; `-1` = sin aviso (`AppointmentReminder`) |
| `recurrenceRaw`, `recurrenceEnd` | Regla de la serie (`AppointmentRepeat`: diaria, semanal, cada 2 semanas, mensual) y su último día |
| `seriesID`, `occurrenceStart` | En una repetición guardada aparte: la serie y el inicio que sustituye |
| `invoiceID`, `estimateID` | Factura o estimado creados desde la cita |

**Series:** la primera cita guarda la regla y no se enseña tal cual; las repeticiones se calculan
(`AppointmentRecurrence` en ChirograCore). Solo se guarda una repetición cuando cambia (hecha, cancelada, movida,
facturada o borrada). «Esta y las siguientes» corta la serie la víspera y empieza otra; las repeticiones ya hechas,
canceladas o facturadas que caían después quedan como citas sueltas, con su historia.

Ojo: `CompanyOwnership.ownedTypesV4` deja fuera los modelos nuevos (`SchemaV6.addedTypes`): la migración 3 → 4 trabaja sobre un almacén del 4, que no
tiene esas tablas.

## Impuestos estimados (`EstimatedTaxSetting`, `EstimatedTaxPayment`)

- **Ajuste** por empresa: `percent` (25 por defecto, entre 1 y 60) y `showsCard`. Va en un modelo propio y no en
  `Company`, porque `Company` tiene relación con `Attachment` (el logo) y cambiarla arrastraría otras clases. Si iCloud
  trae dos, vale el más antiguo.
- **Pago al IRS:** `taxYear`, `period` (1…4), fecha, monto, cuenta de la que salió y su asiento: **debe a retiros del
  dueño (3100), haber a la cuenta de dinero**, origen `EntrySource.estimatedTax` (una versión anterior lo lee como manual).
  No toca la ganancia: es el impuesto personal del dueño. Quitarlo revierte el asiento.
- **Periodos del 1040-ES** (`EstimatedTaxCalendar`, ChirograCore): ene–mar → 15 abr, abr–may → 15 jun, jun–ago → 15 sep,
  sep–dic → 15 ene del año siguiente; si el 15 cae en fin de semana, el lunes. No son trimestres de calendario. El pago
  «que toca» es el del periodo de hoy, salvo que el anterior aún no venza y no esté pagado.
- `Bookkeeper+EstimatedTax.swift`: `estimatedTaxSummary(today:basis:)` (tarjeta y pantalla: ganancia del periodo hasta
  hoy, a apartar, días que faltan, los cuatro pagos del año), `setEstimatedTax(percent:showsCard:)`,
  `recordEstimatedTaxPayment` y `deleteEstimatedTaxPayment`. Pruebas en `EstimatedTaxTests`.
- **Dónde va en las pantallas** (canvas): tarjeta arriba en Inicio y en Reportes; pantalla «Impuestos estimados» como
  subsección de Impuestos en la barra lateral (iPad y Mac) y desde Más en el iPhone; hoja «Pago al IRS».

## Servicios de la agenda (`Bookkeeper+Agenda.swift`)

`appointments(in:)` y `appointments(forCustomer:in:)` (dan `AppointmentOccurrence`), `createAppointment`,
`updateAppointment(_:with:scope:)`, `setStatus(_:of:)`, `link(_:invoiceID:estimateID:)` y
`deleteAppointment(_:scope:)`. Todo pasa por la bitácora (`AuditSubject.appointment`, «Cita», área Ventas), la copia
de seguridad (`scripts/gen-backup.py`, 42 modelos) y «Borrar todo». Pruebas en `AgendaTests` y `MigrationTests`.

En la app el documento se llama **estimado** («Nuevo estimado»), aunque el canvas diga «Crear presupuesto»:
«presupuesto» ya es el de Budgets.

## Antes de subir un build de la 1.4

1. En el Mac con iCloud: `-qa.esquemaCloudKit 1` y que el usuario haga «Deploy Schema Changes…» a Producción.
2. Probar en Producción en sus aparatos que la agenda sincroniza (CONTEXTO, «Lo aprendido»).
3. Las copias de la 1.4 llevan esquema 6.0.0: la 1.3 no las restaura (avisa de que son de una versión más nueva).
