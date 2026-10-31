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
cd Packages/ChirograKit && swift test
```

```bash
xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

```bash
xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Si cambias `project.yml`, regenera el proyecto con `xcodegen generate`.

## Sincronización con iCloud

El modelo de datos ya cumple las reglas de CloudKit, pero la capacidad de iCloud no viene activada para que el proyecto compile con cualquier cuenta (los equipos personales no admiten iCloud). Para activarla:

1. En Xcode, target **Chirogra** › *Signing & Capabilities*, elige tu equipo.
2. Añade **iCloud** con **CloudKit** y el contenedor `iCloud.com.chirogra.app` (o cambia `ChirograApp.cloudKitContainer`).
3. En la app, *Ajustes › iCloud, copias y seguridad › Sincronizar con iCloud*, y vuelve a abrirla.

Sin la capacidad, la app usa un almacén local aunque el interruptor esté activado.

## Estado

Esqueleto del MVP (ver DISEÑO §3.1 y §10). Funciona: alta de empresa, plan de cuentas, asientos manuales y reversiones, clientes, facturas con sales tax, cobros, anulación, proveedores, facturas por pagar y pagos, gastos, tasas y grupos de impuesto, reportes (resultados, balance general, balanza, antigüedad) con exportación CSV, cierre de periodo, bloqueo con Face ID y datos de ejemplo.

Pendiente del MVP: PDF y envío de facturas, notas de crédito en la interfaz, adjuntar recibos, copia de seguridad exportable, traducción al inglés y el ícono definitivo exportado del canvas.
