# Datos v5: esquema 5.0.0 (versión 1.2)

Rama `version-1.2` (10-nov-2026). Tres cosas: asientos de ajuste del contador, bitácora de cambios y Banca (dividir un
movimiento y motivo al excluir). Decisiones del usuario del 10-nov: en la bitácora, «quién» es **el aparato** en que se
hizo; la marca del contador sale **encendida de entrada con el plan para contadores** y se puede apagar.

## Esquema 5 (`SchemaV5.swift`)

Solo añade, todo `String = ""`. La migración 4 → 5 es ligera. Los demás modelos son los de `SchemaV4` (como el 3
reutilizó los del 2). Las versiones del 4 de las dos clases que cambian quedan **congeladas**: solo las propiedades
guardadas, y sus huellas están en `FrozenSchemaTests.hashesV4`.

| Modelo | Propiedad nueva | Para qué |
|---|---|---|
| `AuditEvent` | `device` | Aparato en que se hizo el cambio (`Bookkeeper.deviceName`) |
| `AuditEvent` | `changeDetails` | Antes → después por campo, una línea cada uno; o lo que tenía lo borrado |
| `BankTransaction` | `ignoreReason` | Motivo con que se excluyó |

Lo que **no** cambia el esquema:
- **Ajuste del contador:** `EntrySource.accountantAdjustment`. Se guarda como texto y la 1.1 lo lee como `manual`.
  `EntrySource.isManual` cubre los dos.
- **Movimiento dividido:** crea un gasto con varias líneas (si es una salida) o un depósito con varias líneas al haber
  (si es una entrada). `Bookkeeper.splitParts(of:)` las lee del documento.

Ojo: la migración 3 → 4 recorre los modelos con las clases del 4 (`CompanyOwnership.ownedTypesV4`). Con las del 5, Core
Data no encuentra las propiedades nuevas y la app se cierra (pasó en las pruebas).

## Servicios

- `Bookkeeper+AuditLog.swift`: `audit(…, changes:)` pone el aparato en cada evento. Además están `AuditChanges` (el antes
  y el después), `AuditSnapshot` (fotos de cliente, proveedor, artículo y gasto), `logChange`/`logSave` (para las
  pantallas), `auditLog(entityID:limit:)`, `deleteDraft(_:)` y `deleteEstimate(_:)`.
- Ahora también dejan rastro: excluir (con motivo), devolver a la bandeja, dividir, anular factura, descartar
  conciliación, renombrar presupuesto, editar un gasto (campo por campo, también uno sin asiento) y altas y ediciones de
  clientes y proveedores.
- `Bookkeeper.categorize(_:splitInto:)`: dos partes o más, que sumen el importe, ninguna a una cuenta de dinero.
  `ignore(_:reason:)`.

## Pantallas

- **Contabilidad:** interruptor «Ajuste del contador» en el asiento a mano, filtro por origen («Del contador» y los
  demás) en el diario de los tres aparatos (Mac: tabla; iPad: columna; iPhone: botón de filtro de la barra, desde el
  build 33) y etiqueta «Del contador» en la fila del iPhone y del iPad. La reversión de un ajuste del contador también
  lleva su origen (`reverse` copia `.accountantAdjustment`; decisión del usuario del 11-nov). Las plantillas (aportación,
  retiro, traspaso) quedan como manuales: las hace el dueño (decisión del 11-nov).
- **Bitácora de cambios** (`Accounting/AuditLogView.swift`): Contabilidad en la barra lateral y en «Más» del iPhone. En
  el iPhone y el iPad, lista por días con su detalle; en el Mac, tabla e inspector. Filtros: Todo, Ventas, Gastos, Banca,
  Contabilidad, Empresa y Borrados.
- **Banca** (canvas `BancaRevisar`): tercer segmento «Dividir» y, al excluir, «Motivo de exclusión» con los motivos del
  canvas y «Otro motivo», que añadí yo. Los atajos (deslizar, menú contextual, botón del Mac) preguntan el motivo con un
  diálogo.
- **Bienvenida del contador** (canvas «Chirogra — Contadores», https://claude.ai/artifact/EYXyE1QxcnfgvuxTbz6bzT, opción A
  elegida por el usuario el 10-nov; `Onboarding/AccountantWelcome.swift`). El carrusel tiene una sexta página, «¿Para
  quién llevas los libros?», con «Mi negocio» o «Los de mis clientes» (`WelcomeAudience`, ajuste `welcome.audience`).
  - «Mi negocio» va al alta de siempre.
  - «Los de mis clientes» abre «Chirogra para contadores», con «Dar de alta mi primer cliente» (el alta dice «Tu primer
    cliente») e «Importar copia de un cliente» (`restoreCompany(.newCompany)`).
  - Tras el alta, la pantalla de planes sale con el plan para contadores.
  - Con el plan para contadores ya activo, «Los de mis clientes» sale marcada, salvo que la persona haya elegido a mano
    (decisión del usuario del 10-nov).
  - QA: `-qa.bienvenida 6`, `-welcome.audience accountant`, `-qa.introContador 1`.
- **Bitácora, textos guardados:** el resumen y el antes/después se guardan como texto en el idioma de la app en ese
  momento; si se cambia de idioma, la bitácora queda mezclada (aceptado por el usuario el 11-nov). Fechas e importes con
  el formato de la app (`AuditFormat`: «5 nov 2026», «−$43.10»). Guardar sin cambiar nada no deja evento.
- QA: `-qa.seccion auditLog` (Mac), `-qa.bitacora 1` y `-qa.diario 1` (iPhone, con `-qa.pestana settings`), `-qa.bitacoraMuestra 1`,
  `-qa.revisarModo dividir|excluir`, `-qa.prueba12 1` (empresa «Prueba 1.2 LLC» con todo lo nuevo, para probar iCloud).

## Antes de subir un build

1. ~~En el Mac con iCloud: `-qa.esquemaCloudKit 1` y «Deploy Schema Changes…» a Producción.~~ **Hecho el 10-nov.**
2. Probar en Producción en sus aparatos (CONTEXTO, «Lo aprendido»).
3. `MARKETING_VERSION` 1.2.0 y el build nuevo.

## Tasas de ciudad por código postal (1.2, decisión del usuario, 11-nov)

Hoy solo se llena sola la tasa del estado (`StateSalesTax`, los 50). La búsqueda por código postal
(`PostalSalesTax.swift`, `PostalTaxTableLoader`, «Usar la tasa de Austin…» en el alta) está hecha pero apagada:
`remoteURL = nil` y sin tabla real (la de `-qa.tablaZip muestra` solo trae 78701/78702). Falta: elegir la fuente
(archivos de cada estado, los gratuitos del Streamlined Sales Tax, o una comercial revisando su licencia), generar el
JSON, publicarlo en chirogra.com (`sitio/`), poner `remoteURL` y el permiso `com.apple.security.network.client` en el
Mac, y mantenerla al día (las tasas cambian cada trimestre).

**Decisión (11-nov):** fuentes oficiales y gratuitas de los estados, no las tablas de Avalara (licencia sin aclarar y
es competencia) ni servicios de pago (eso, con servidor, en la 2.0). Primero los 23 estados del Streamlined Sales Tax
(un solo lector: archivos de tasas y de límites, trimestrales) y Texas, California, Florida, New York e Illinois, cada
uno con su lector. Para pasar de condado o ciudad a ZIP donde el estado no lo da, el cruce ZIP–condado de HUD. Un
programa en `scripts/` genera el JSON y se publica en chirogra.com; cada trimestre se vuelve a correr. El ZIP no
coincide con los límites fiscales: un ZIP puede tener varias tasas; la tabla guarda la que cubre más y la app sigue
diciendo «aproximada». Ojo: en New Jersey 0 % de ciudad es lo correcto (6.625 %
en todo el estado, salvo las Urban Enterprise Zones).

**Hecho (11-nov, sin commitear hasta que el usuario lo pida):** `scripts/tasas/` — `descargar.sh <carpeta>` baja los
archivos oficiales y `python3 -I scripts/tasas/generar.py --datos <carpeta> --salida
Packages/ChirograKit/Sources/ChirograData/Resources/sales-tax-zip.json` arma la tabla (una tasa por línea). La tabla
**viaja dentro de la app** (recurso de ChirograData, `PostalTaxTable.bundled()`): funciona sin internet y el Mac no
necesita permiso de red; `remoteURL` sigue en `nil` (si algún día se publica en chirogra.com, la app usa la más
reciente). Cada trimestre: correr los dos programas, revisar el resumen por estado y subir un build.

- Streamlined (19 estados con impuesto local): AR GA IA KS MN NC ND NE NV OH OK SD TN UT VT WA WI WV WY. Por ZIP, la
  combinación condado + ciudad + distritos de sus registros de dirección (si no hay, ZIP+4; si no, el ZIP entero). La
  tasa estatal es la de `StateSalesTax.swift` y el resto va como local (Nevada pone todo en el condado).
- TX (`city-rates.xlsx`; los archivos por dirección del Comptroller dan 403 a los programas), CA (Excel del CDTFA), IL
  (archivo de ancho fijo del IDOR; las ciudades «por dirección» toman su registro R00), FL (DR-15DSS, recargo por
  condado), NY (Publication 718). ZIP → ciudad o condado con los archivos de relación del Census 2020: manda el lugar
  habitado más grande del ZIP; si es un CDP, el condado.
- Solo tasa estatal: CT DC IN KY MA MD ME MI NJ RI (Lodi 07644 → New Jersey 6.625 %).
- Sin tabla todavía (la app dice «No hay una tasa para … escríbela a mano»): AL AK AZ CO HI ID LA MO MS NM PA SC VA y
  los que no tienen sales tax.
- Pruebas: `PostalTaxTableTests` (Austin 8.25, Los Angeles 10.25, Miami 7, NYC 8.875, Chicago 10.5, Lodi 6.625).
