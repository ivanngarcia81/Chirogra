# Chirogra

Contabilidad clara para negocios pequeños y trabajadores independientes en EE. UU. App nativa para iPhone, iPad y Mac hecha con SwiftUI y SwiftData, con contabilidad de doble partida real por debajo.

- Diseño técnico: [docs/DISEÑO.md](docs/DISEÑO.md)
- Diseño de interfaz: canvas de Claude Design enlazado en la sección 7 del diseño técnico.

## Estructura

```
App/                         App multiplataforma (iOS 26+ / macOS 26+): punto de entrada y assets
Packages/ChirograKit/
  Sources/ChirograCore/      Dominio puro: dinero en centavos, validación de doble partida,
                             sales tax, reglas de contabilización y reportes
  Sources/ChirograData/      Modelos SwiftData (esquema versionado, compatible con CloudKit)
                             y Bookkeeper, el único punto de escritura contable
  Sources/ChirograUI/        Sistema de diseño (tokens del canvas) y pantallas
  Tests/                     Swift Testing: dominio y contabilización de punta a punta
project.yml                  Definición del proyecto para XcodeGen
Chirogra.xcodeproj           Proyecto generado (se puede abrir directamente)
```

## Requisitos

- Xcode 27 (Swift 6.2 o posterior)
- iOS / iPadOS / macOS 26 o posterior

## Compilar y probar

```bash
scripts/verificar.sh            # pruebas del paquete + apps de iOS y Mac compiladas + número de build (unos minutos)
scripts/verificar.sh --rapido   # solo las pruebas
```

Es lo mismo que corre GitHub Actions en cada push (`.github/workflows/pruebas.yml`). Las **pruebas de interfaz**
(`UITests/`, objetivo `PruebasInterfaz`: cobrar, anular un cobro, emitir una factura y base caja en Reportes, tocando la
app en el simulador del iPhone con los datos de ejemplo) se corren con `scripts/interfaz.sh` (unos 4 minutos); Actions
las corre en un trabajo aparte. Las pruebas sueltas:
`cd Packages/ChirograKit && swift test --skip ScreenSmokeTests` (`ScreenSmokeTests` falla desde el build 54 por
`ImageRenderer`, pendiente). Para probar la migración con un almacén real de una versión publicada:
`CHIROGRA_STORE=/ruta/Chirogra.store swift test --filter MigrationTests`.

Si cambias `project.yml`, regenera el proyecto con `xcodegen generate` (y restaura `App/Chirogra.entitlements` con
`git checkout`: XcodeGen le quita `ubiquity-kvstore-identifier`).

## Idiomas

La app está en español (idioma de origen) e inglés. Los textos viven en `App/Localizable.xcstrings`, en el target de la app: las vistas del paquete usan `Text("…")` y `String(localized:)`, que buscan en el bundle principal. Como Xcode no sincroniza solo los textos del paquete con ese catálogo, después de añadir o cambiar textos:

```bash
scripts/sync-strings.sh
```

y traduce en Xcode los textos nuevos. Las pruebas de `ChirograUITests` fallan si falta el inglés de algún texto.

Los textos de la interfaz cambian con el idioma del teléfono, pero los datos guardados no. El plan de cuentas (también el de los datos de ejemplo) y los memos que genera la app se crean en el idioma que tenga el teléfono en ese momento y ya no cambian, igual que los clientes, proveedores y descripciones que escribe el usuario. Las fechas, los importes y el nombre de la moneda siguen la región del teléfono; el CSV usa fechas ISO para las hojas de cálculo.

## Sincronización con iCloud

La capacidad de iCloud (CloudKit, contenedor `iCloud.com.chirogra.app`, y el almacén de clave-valor para las empresas
borradas) está en `App/Chirogra.entitlements` y se firma con el equipo de la app. Con otra cuenta de desarrollo sin
iCloud, la app abre el mismo almacén solo en local y la franja de iCloud avisa de que no sincroniza. Cada aparato decide
en *Ajustes › iCloud y copias › Sincronizar con iCloud*.

## Estado

Versiones en App Store Connect: la **1.0** (build 15) está aprobada; la **1.3.0** (build 64), que junta la 1.1, la 1.2
y la 1.3, está en revisión. Lo que hay hoy en el código (rama `version-1.3`):

- **Alta y empresas:** alta con sector (plan de cuentas por plantilla), varias empresas, datos de ejemplo, bienvenida y
  recorrido de la primera vez; plan para contadores con panel de clientes.
- **Contabilidad:** plan de cuentas, asientos manuales y ajustes del contador, reversiones, libro mayor, cierre de
  periodos con contraseña y «cambios después del cierre», bitácora de cambios.
- **Ventas:** clientes, estimados que se convierten en factura, facturas con descuento y sales tax (también incluido en
  el precio), edición de facturas emitidas sin cobros, PDF, envío y recordatorios, enlace de pago, cobros y anulación de
  cobros, notas de crédito, saldo a favor aplicado o reembolsado, recurrentes.
- **Compras:** proveedores con W-9 y aviso 1099, facturas por pagar, pagos programados y en lote, gastos con recibo
  (escaneo y lectura del texto con Vision), reclasificación en lote.
- **Banca:** importación de extractos, bandeja de movimientos con reglas, dividir y excluir, traspasos, conciliación.
- **Sales tax:** tasas y grupos, sugerencia por código postal (27 583 ZIP de 34 estados, aproximada y con fecha;
  `scripts/tasas/`), resumen por periodo y pago a la agencia.
- **Reportes:** resultados, balance general y balanza en base devengado o **caja**, flujo de efectivo, antigüedad,
  sales tax, presupuesto contra real, deducibles por línea del formulario y paquete para el contador, con CSV.
- **Seguridad y datos:** bloqueo con Face ID, iCloud, copia `.chirogra` con contraseña (AES-GCM) y suma SHA-256,
  restaurar y deshacer, pantalla de recuperación si la base no abre.

La copia de seguridad se genera desde los modelos: después de cambiar el esquema, ejecuta `scripts/gen-backup.py`
(`BackupTests` falla si no está al día).

**Previsto, no hecho:** la 1.4 (agenda y asistente con IA, [docs/PLAN-1.4.md](docs/PLAN-1.4.md)) y la 2.0 con servidor
(Plaid, Stripe, el contador dentro de los libros, nómina; [docs/PLAN-2.0.md](docs/PLAN-2.0.md)). Hoy no hay conexión
directa con bancos: los movimientos entran por archivo.
