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

- **Contabilidad:** interruptor «Ajuste del contador» en el asiento a mano, filtro «Del contador» en el diario del iPad
  y el Mac, y etiqueta «Del contador» en la fila del iPhone.
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
- QA: `-qa.seccion auditLog` (Mac), `-qa.bitacora 1` (iPhone), `-qa.bitacoraMuestra 1`,
  `-qa.revisarModo dividir|excluir`, `-qa.prueba12 1` (empresa «Prueba 1.2 LLC» con todo lo nuevo, para probar iCloud).

## Antes de subir un build

1. ~~En el Mac con iCloud: `-qa.esquemaCloudKit 1` y «Deploy Schema Changes…» a Producción.~~ **Hecho el 10-nov.**
2. Probar en Producción en sus aparatos (CONTEXTO, «Lo aprendido»).
3. `MARKETING_VERSION` 1.2.0 y el build nuevo.
