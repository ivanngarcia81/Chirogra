# Chirogra: contexto para retomar en otro chat

Resumen del chat de coordinación de Chirogra (desarrollo + QA), al 2 de noviembre de 2026. Léelo antes de seguir. El diseño técnico completo está en [DISEÑO.md](DISEÑO.md); aquí solo va el estado, las decisiones del usuario y cómo se trabaja.

## Estado actual

- **Versión aprobada:** el rediseño nativo, aprobado por el usuario y subido a `main` en GitHub (github.com/ivanngarcia81/Chirogra) el 2-nov. La anterior era `038b168`.
- **Instalada en:** iPhone 17 Pro Max, iPad Pro 12,9″ y Mac (`/Applications/Chirogra.app`, Release) con `integracion-rediseno` `8952b61` (Mac con tabla + inspector; hojas de editor menos apretadas), el 2-nov.
- **Rediseño nativo (2-nov), hecho en la rama `integracion-rediseno` y ya en `main` (subido el 2-nov).** El usuario pidió rehacer la app con el canvas actualizado («Claude code actualizó el diseño»), lo que deja sin efecto el descarte de `7a8b97f`. El sistema y el mapa por áreas están en [REDISEÑO-NATIVO.md](REDISEÑO-NATIVO.md). Lo hizo un equipo de agentes en worktrees (`.claude/worktrees/`), uno por tarea, y el coordinador lo fusionó. Para resolver choques del catálogo de textos hay un script de fusión por claves (ver «Fusionar el catálogo de textos» abajo).

## Qué se hizo en este chat (de lo más antiguo a lo más nuevo)

| Commit | Qué |
|---|---|
| `430ccf7` | Barra lateral, estados de iCloud, detalles menores |
| `1d3a31d` | Confirmación de borradores |
| `9df80c1`, `9a4990c`, `46c3cfd` | Aviso de «¿Descartar los cambios?» en 12 editores, sin avisos fantasma (token débil por editor + 1,2 s de margen) |
| `68ebad9` | Ícono de la app desde Icon Composer (`App/AppIcon.icon`) |
| `f21e0bf` | Cabecera, botones de la barra y botones primarios en Liquid Glass del sistema, sin morado |
| `752c879` | Columna maestro-detalle en Facturas, Clientes, Gastos, Proveedores, Por pagar, Banca, Asientos y Plan de cuentas (`Shell/MasterDetail.swift`, nuevo `BillDetailView`) |
| `10bf2c5`, `281d573` | Mac: que no parezca un iPhone estirado (densidad de Mac, un solo título, barra lateral de 220 pt, hojas con `.confirmationAction` / `.cancellationAction`, contraste AA de la fila seleccionada) |
| `6bb7a97`, `038b168` | Títulos de la columna maestro visibles en el iPad; «+» solo como ícono en Por pagar y Plan de cuentas |

### Rediseño nativo (2-nov, de `integracion-rediseno`, ya en `main`)

| Commit | Qué |
|---|---|
| `d343fa1` | iPad vertical: la barra lateral se cierra sola en las páginas de lista; barra de 280 pt en todas las páginas |
| `de93afd` | Hojas de editor en el iPad: alto de página y 760 pt de ancho (`editorSheetSizing`) |
| `9476336` | Título pequeño en línea en todos los detalles del iPad |
| `2742f53` | VoiceOver: «Depositar en» y «Fecha» con nombre y valor en Registrar pago |
| `62f5b58` | Base del rediseño nativo (`Palette`, `Components`, `docs/REDISEÑO-NATIVO.md`) |
| `4db4ec2` | Botón principal en vidrio sin relleno; decisiones del usuario sobre el canvas |
| `96c44e1` | Área A: Inicio, Reportes, Impuestos |
| `7fdc121` | Área B: Ventas y Clientes |
| `6975c8f` | Área C: Gastos, Proveedores, Por pagar, Banca, Contabilidad |
| `5229973` | Área D: pestañas, barra lateral, columna maestro, estados, Alta, Ajustes |
| `106c441` | QA del coordinador: cabecera de la factura (total si está pagada; «Por cobrar de un total de…») y gastos sin «−» en la columna maestro |

Visto por el coordinador en simulador (iPhone 17 Pro e iPad Pro 13″, claro y oscuro, horizontal y vertical): las 5 pestañas del iPhone, las 8 páginas del iPad, detalle de factura y de gasto. Compila para iOS y Mac; `swift test` pasa. **Sin ver: el Mac en pantalla** (la Debug comparte datos con la app instalada), VoiceOver de verdad, iPad con letra grande, registrar un asiento de punta a punta.

## Decisiones del usuario (no deshacer sin preguntar)

- **Liquid Glass** en cabecera, barra y botones primarios, en todas las páginas. Nada de botones morados. **Botón principal en vidrio sin relleno** aunque el canvas lo rellene de Tinta (2-nov).
- **Rediseño nativo según el canvas actual** (2-nov): manda el canvas salvo lo que diga esta lista. Pestañas del iPhone Inicio · Ventas · Gastos · Banca · Más (Reportes en «Más»); fila elegida de la columna maestro rellena de Tinta; barra lateral con grupos «Negocio» y «Libros».
- **iPad: maestro-detalle; Mac: tabla + inspector (2-nov).** En el iPad, las páginas de lista siguen con columna maestro + detalle. En el Mac son como el canvas (`MacVentas`, `MacClientes`, `MacGastos`…): barra lateral + contenido, tabla a todo el ancho e inspector de ~300 pt a la derecha con lo elegido (ver [REDISEÑO-NATIVO.md](REDISEÑO-NATIVO.md), «Mac: tabla + inspector»). Hechas las 8 páginas de lista (Facturas, Clientes, Gastos, Proveedores, Por pagar, Banca, Asientos, Plan de cuentas) y el inspector de Inicio, Reportes e Impuestos.
- **Mac con densidad de Mac**, no de iPhone (objetivos de 28 pt en Mac, 44 pt en iOS: `Metrics.target`).
- **Ícono de la app** = el de Icon Composer. El **logo de la empresa** queda para después.
- **Modo oscuro en Mac:** «salta por ahora esa parte». QA prueba el Mac solo en claro.
- Todo esto también está anotado en [DISEÑO.md §7.4](DISEÑO.md).

## Reglas de trabajo

- **Subir a GitHub solo cuando el usuario lo pida.** Subir el commit aprobado explícitamente: `git push origin <hash>:refs/heads/main`, para no subir un commit sin revisar.
- **Instalar en los aparatos** cuando el usuario lo pida (ver abajo).
- Fase 2 queda fuera: OCR, bandeja del banco y conciliación, presupuestos, usuarios y permisos, varias empresas.
- Las claves de Plaid solo irán en un backend futuro (fase 3), nunca en la app.
- Accesibilidad: 44 pt en iOS, Dynamic Type, VoiceOver, contraste AA.
- Bilingüe español/inglés; las fechas numéricas siguen la región del aparato.
- Avisar al usuario antes de borrar cualquier cosa de su computadora. No cambiar ajustes del sistema ni de Xcode.
- El canvas de Claude Design es de solo lectura: https://claude.ai/artifact/Ai344mUq54BECC4Pw4quV9

### Fusionar el catálogo de textos

Si dos ramas añaden textos a `App/Localizable.xcstrings`, git choca. Se resuelve por claves: sacar las tres versiones (`git show ":1:App/Localizable.xcstrings"`, `:2:`, `:3:`; en zsh, con comillas o `${n}`) y unirlas con un script que conserve las claves de las dos ramas y, si una clave cambió en las dos, elija a mano. Escribir el JSON con `indent=2` y `separators=(',', ' : ')` como Xcode. La prueba `StringCatalogTests` exige el inglés con los mismos marcadores que el español (`%@`, no `%1$@`).

### Flujo con dos sesiones

1. **Desarrollo** hace un bloque, termina con «SECCIÓN LISTA» y un commit local, sin subir.
2. El coordinador lee el commit (`git show`) y lo pasa a **QA** con los puntos a probar.
3. QA da un veredicto y la ruta de su informe; QA no edita el repo.
4. El coordinador pasa los hallazgos a desarrollo y le informa al usuario en español.

## Compilar e instalar en los aparatos

- Equipo de firma: `4N9XEU7F4P`. Bundle id: `com.chirogra.app`.
- iPhone 17 Pro Max: `00008150-0005793E3EC0401C`
- iPad Pro 12,9″ (5.ª gen.): `00008103-001439A91E6B001E`

Compilar desde un clon limpio del commit aprobado, en una carpeta temporal (`$T`):

```bash
git clone -q ~/Documents/GitHub/Chirogra $T/src && git -C $T/src checkout -q <hash>
```

```bash
cd $T/src && xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath $T/dd DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates build
```

```bash
xcrun devicectl list devices | grep physical
```

```bash
xcrun devicectl device install app --device <UDID> $T/dd/Build/Products/Debug-iphoneos/Chirogra.app
```

Para el Mac, compilar con `-configuration Release -destination 'platform=macOS'` y luego:

```bash
osascript -e 'tell application id "com.chirogra.app" to quit'; rm -rf /Applications/Chirogra.app && ditto $T/dd/Build/Products/Release/Chirogra.app /Applications/Chirogra.app && codesign -v /Applications/Chirogra.app
```

Problemas conocidos: si el aparato sale «desconectado», reintentar. «The developer disk image could not be mounted» = el aparato está bloqueado; desbloquearlo y reintentar.

## Pendiente

Probado por el usuario el 2-nov y funciona: Escape y Return en los editores del Mac, ⌥⌘I, doble clic, ordenar columnas, soltar un recibo, «Registrar pago» en la hoja, y el iPad sin el anillo de foco.

**Sin comprobar**
- VoiceOver de verdad (iPhone, iPad y Mac) e iPad con letra grande.
- Registrar un asiento de diario de punta a punta; revertir y archivar cuentas en el Mac.
- Estado vacío del Mac (empresa sin datos).
- Las hojas del Mac siguen la apariencia del sistema (el Mac del usuario está en oscuro); `-qa.apariencia` solo cambia la ventana de la copia de prueba, no sus hojas.

**Lo que dibuja el canvas y la app no tiene (decidir si se construye; necesita datos o funciones nuevas)**
- Pagos programados y en lote, gastos recurrentes, «Programar pago», «Impuesto incluido», W-9.
- Editar un gasto o una cuenta ya contabilizados; editar una tasa de impuesto.
- Plantilla de factura, «Para/Asunto» al enviar, persona de contacto del cliente, «vista por el cliente» y recordatorio enviado.
- Campana de avisos; plan de cuentas agrupado por tipo con triángulos (la tabla común del Mac solo admite filas planas).

**Fase 2 (fuera del MVP)**: OCR, bandeja del banco e importar/conciliar (Plaid en un backend), usuarios y permisos, varias empresas, deducibles y «Exportar para mi contador».

**Más adelante**
- Logo de la empresa (el ícono de la app ya está: `541169a`).
- Subir a `DesignSystem` las piezas que los agentes hicieron dentro de cada pantalla: grupos de filas, `ComparisonBars`, cebra de tablas, monogramas de varios tamaños, `ActivityMark`, `LineEditRow`.
- QA no debe tocar el simulador de iPad `BEB1EA39`: ahí corren las pruebas de interfaz de otro proyecto (Tamio).
