# Rediseño nativo: sistema y mapa de pantallas

Traducción a SwiftUI del canvas **«Chirogra — Diseño de app»** (https://claude.ai/artifact/Ai344mUq54BECC4Pw4quV9, versión `1793628078-9aef`, leída el 2 nov 2026), cuyo tablero `Main.dc.html` se titula **«Sistema nativo (iOS 26 · iPadOS 26 · macOS Tahoe)»**. Esta versión del canvas sustituye a la de [DISEÑO.md §7.3](DISEÑO.md) (paleta propia con `surface`, `ink3`, chips con fondo…): donde no coincidan, manda este documento. Las decisiones del usuario de [DISEÑO.md §7.4](DISEÑO.md) siguen en pie salvo lo anotado en §4.

La base (primera tanda) ya está hecha en `DesignSystem/Palette.swift`, `DesignSystem/Components.swift`, `Sales/SalesWideViews.swift` (`TableCard`, `TableRow`) y `App/Assets.xcassets/AccentColor`. Las pantallas compilan sin cambios y ya toman el aspecto nuevo de los componentes; lo que falta es rehacer cada pantalla (segunda tanda, §3).

---

## 1. El sistema

### 1.1 Color

Un solo color propio, **Tinta**, como `AccentColor` (el `tint` de toda la app). Todo lo demás son colores semánticos del sistema: el modo oscuro y «Aumentar contraste» salen del sistema.

| Token (`Palette.`) | Claro | Oscuro | Uso en el canvas |
|---|---|---|---|
| `brand` (= `AccentColor`) | `#3A3FD1` | `#9A9EFF` | Texto e iconos de acento, enlaces («Ver todo»), pestaña activa, ingresos en gráficas, filtro activo |
| `brandFill` | `#3A3FD1` | `#5458E6` | Relleno bajo texto blanco: botón principal, fila elegida (Mac, iPad), barra lateral del iPad, acción «Escanear» |
| `onBrandFill` | blanco | blanco | Texto sobre `brandFill` |
| `brandWash` | Tinta 12 % | `#9A9EFF` 18 % | Selección suave |
| `background` | `systemGroupedBackground` | ídem | Fondo de pantalla (Mac: `controlBackgroundColor`, blanco / `#1E1E1E`, el `--win` del canvas) |
| `surface` | `secondarySystemGroupedBackground` | ídem | Celdas y tarjetas (Mac: `#F5F5F7` / `#262628` con borde de `separator`, el `--row2`) |
| `surface2` | `tertiarySystemFill` | ídem | Buscador, segmentado, botón secundario, hoja de calendario (`--fill`) |
| `fill2` | `systemFill` | ídem | Interruptor apagado, resto de una barra (`--fill2`) |
| `separator` | `separator` | ídem | Líneas de 0,5 pt |
| `ink` | `label` | ídem | Texto principal, importes (también los de salida) |
| `ink2` (= `ink3`) | `#6C6C70` | `#98989F` | Texto secundario (`secondaryLabel` opaco: AA en texto pequeño) |
| `chevron` | `#BABABF` | `#5C5C61` | Chevrons y anillos, nunca texto |
| `positive` | `#1F7A35` | `#30D158` | Texto «Pagada», variación favorable, entradas de dinero |
| `negative` | `#D70015` | `#FF6961` | Texto «Vencida», destructivo |
| `warning` | `#B54700` | `#FF9F0A` | Texto «Pago parcial», «por revisar» |
| `info` | `#0064A0` | `#64D2FF` | Texto «Vista», información |
| `green` `red` `orange` `yellow` `blue` `teal` `indigo` `purple` `pink` `gray` | colores del sistema | | Puntos de estado, iconos de fila tipo Ajustes, categorías |
| `income` / `expense` / `expenseBar` | Tinta / systemOrange | | Gráficas de ingresos y gastos |
| `bankAccount` / `creditCard` | systemBlue / systemIndigo | | Icono de cuenta bancaria / tarjeta |
| `monogram` | degradado `#A3A3A8 → #86868B` | | Monogramas de cliente, proveedor, empresa y usuario |
| `logoFill` / `logoMark` / `accent` | `#3A3FD1` / blanco / azafrán `#F2B33D` | igual | Solo el logotipo (`LogoMark`) |

Significados (tablero `Main`): Ingresos = acento · Gastos = systemOrange · Pagada/al día = systemGreen · Vencida/excluir = systemRed · Vista/info = systemTeal · Cuenta bancaria = systemBlue · Tarjeta = systemIndigo.

Tokens que se conservan solo para que compile lo viejo y que la segunda tanda debe dejar de usar: `onBrand` (tarjetas rellenas de marca, que el canvas ya no tiene), `outflow`/`outflowWash` (ahora `ink`/`surface2`), `…Wash` de estados (ya no hay cápsulas de estado), `sidebar`.

### 1.2 Tipografía

SF Pro con Dynamic Type; ningún tamaño fijo salvo cifras dentro de iconos.

| Estilo | iPhone/iPad | Mac | Uso |
|---|---|---|---|
| `.largeTitle` bold | 34 | — | Título de pantalla (en el Mac, el de la ventana: 15 bold con subtítulo de 11) |
| `Font.cardTitle` = `.title3` bold | 20 | `.headline` 13 bold | Título de un grupo fuera de la tarjeta («Ingresos y gastos», «Por cobrar») |
| `.body` | 17 | 13 | Filas, valores, botones |
| `.subheadline` | 15 | 11 | Subtítulo bajo el título grande, detalles, etiquetas de cifras grandes |
| `.footnote` (= `Font.label` en iOS) | 13 | — | Subtítulo de fila, estado, encabezado de sección, pies |
| `Font.label` en Mac = `.subheadline` semibold | — | 11 | Cabeceras de tabla y de inspector |
| `.caption` | 12 | 10 | Nombre de acción rápida o de la ficha |
| `Font.amount(_:)` | 36–40 / 28 / 24 / 22 / 17 bold | | Cifras: siempre `.monospacedDigit()` |

Encabezados de sección **en tipo oración**, nunca en mayúsculas (`SectionLabel` pone `.textCase(nil)`).

### 1.3 Espaciado y forma (`Metrics`)

| | iPhone/iPad | Mac |
|---|---|---|
| `gutter` (margen lateral) | 16 (los títulos de sección, a 32 del borde) | 20 |
| `cardRadius` (grupos, tarjetas) | 24 | 12 (cajas) · `tableRadius` 8 |
| `buttonHeight` (cápsula) | 50 | 28 |
| `target` | 44 | 28 (decisión del usuario) |
| `rowHeight` (fila de dos líneas) | 60 | 28 |
| `iconTile` (icono tipo Ajustes) | 30, radio 8 | 22, radio 6 |
| `avatar` (monograma de fila) | 40 | 28 |
| `fieldRadius` | 12 | 7 |
| Separación entre grupos | 20–26 pt con título; 8–12 entre cifras | 12–16 |

Botones, chips, segmentados, buscador y barra de pestañas: cápsulas. Separadores de 0,5 pt con sangría de 16 desde el borde de la celda (los de `List` ya lo hacen).

### 1.4 Componentes (en `DesignSystem/Components.swift`)

| Componente | Canvas | Ahora |
|---|---|---|
| `.buttonStyle(.primary)` | «Enviar factura», «Registrar $…», «Continuar» | `.glassProminent` en cápsula, `brandFill`, texto blanco semibold, a todo el ancho, `controlSize(.large)` |
| `.buttonStyle(.primaryCompact)` (nuevo) | «Importar mi banco» del estado vacío | Igual, del ancho del texto |
| `.buttonStyle(.secondary)` / `.destructive` | «Vista previa» / «Excluir» | iOS: cápsula `surface2` con texto semibold en Tinta / rojo (`FillCapsuleButtonStyle`); Mac: botón con borde del sistema |
| `headerButton()`, `AddButton` | Botones de vidrio de la barra con el símbolo en `label` | Sin cambios: el vidrio de la barra con `tint(ink)` |
| `glassActionButton()` | — | Sin cambios (`.glass`) |
| `StatusChip` | «● Vencida · 8 días» | Punto de color del sistema + texto en su color AA, sin cápsula. Nuevo parámetro `dot:`. Estados: Borrador gris, Enviada azul (texto `ink2`), Pago parcial naranja, Vencida rojo, Pagada verde, Anulada gris; facturas por pagar: «Por pagar» azul |
| `StatusDot` (nuevo) | Punto de 7 pt (6 en Mac) | |
| `FilterChip` | — (el canvas usa segmentado o menú) | Cápsula `surface2`; la elegida en `brandFill` con texto blanco. **A sustituir** por: |
| `FilterPicker` (nuevo) | Segmentado «Mes · Trimestre · Año», «Total · Parcial», «Gastos · Por pagar · Recurrentes» | Segmentado del sistema hasta 4 opciones; si no caben o con AX, menú |
| `FilterMenu` (nuevo) | Filtro de `Ventas` (botón de filtro de la barra con menú y cuentas, como Mail) | `Menu` + `Picker(.inline)` con `badge`; Tinta si hay filtro |
| `UnderlineTabs` | Secciones de `Gastos` | Segmentado del sistema (misma API) |
| `InitialsTile` | Monograma de `Clientes`, `FacturaNueva` | Círculo con degradado gris e iniciales blancas, 40 pt (los parámetros de color ya no hacen nada) |
| `IconTile` | Iconos de `Mas`, `Gastos`, Cuentas de `Home` | Símbolo blanco en cuadrado de color (30 pt, radio 8); `foreground` es el color del cuadrado (pasar `Palette.blue`, `.orange`…) |
| `DateTile` (nuevo) | «NOV 3» de Por pagar | Hoja de calendario 38×40, mes rojo |
| `LedgerRow` | Fila de dos líneas | Título `.body` regular, subtítulo `.footnote` gris; ~60 pt en lista |
| `SectionLabel`, `Section(title:)` | «Registrar pago», «Actividad» | `.footnote` gris en tipo oración (Mac: 11 semibold) |
| `SectionHeader` (nuevo) | «Por cobrar · Ver todo» | `.title3` bold + enlace en Tinta, fuera de la tarjeta |
| `card()` | Grupo de radio 24 | `surface` radio 24; en el Mac caja `#F5F5F7` con borde y radio 12 |
| `fieldBox()` | `.tf` del Mac, campos de las líneas | iOS: relleno `surface2` radio 10; Mac: `.roundedBorder` |
| `InkValueLabeledContentStyle` | «Número F-1049», «Método Transferencia» | Valor en `ink2` (antes `ink`), misma lógica de saltos |
| `BottomActionBar` / `bottomActionBar` | Barra flotante de `FacturaNueva` | Vidrio (`glassEffect`) que flota con `safeAreaBar` |
| `ProfileHeader` | Cabecera de `ClienteFicha`, `ProveedorFicha` | Centrada: monograma de 84 pt (64 Mac), nombre `.title` bold, detalle gris |
| `ProfileAction` | Llamar · Mensaje · Correo · Factura | Círculo de vidrio de 54 pt con el símbolo en Tinta y el nombre debajo |
| `QuickAction` (nuevo) | Factura · Gasto · Escanear · Cliente de `Home` | Círculo de 58 pt `surface` con símbolo en Tinta; `prominent` en `brandFill` |
| `MiniStat`, `KPITile` | Resumen de tres columnas | Etiqueta `.footnote` gris, cifra `.headline` |
| `KPIGrid` | Cajas de `MacInicio`, `MacVentas`, `iPadInicio` | `card()` con etiqueta gris, cifra de 24 bold; `isBrand` ya no rellena |
| `HeroCard` | «Efectivo disponible», «Ganancia neta» | Tarjeta normal: etiqueta gris, cifra de 36, variación verde/roja (según el signo), detalle gris. Sin relleno de marca |
| `EmptyStateView` | `EstadoVacio`, «Sin resultados» | `ContentUnavailableView` con la acción en `.primaryCompact` |
| `LogoMark` | Icono de `Main` | Siempre `#3A3FD1`, «C» blanca, punto azafrán; radio 9/40 |
| `ErrorBanner` | — | Texto rojo sobre rojo 12 % |
| `TableCard`, `TableRow` (`Sales/SalesWideViews.swift`) | Tablas del Mac | Mac: borde 0,5, radio 8, cabecera de 26 pt (11 semibold gris, sin mayúsculas), filas de 28 con cuerpo de 13. iOS: celda de radio 24 |

### 1.5 Patrones de pantalla (lo que repiten los tableros)

- **iPhone.** Barra con botones de vidrio a la derecha (acciones en un grupo de vidrio, p. ej. «filtro + nuevo»; avatar con monograma en Inicio), título grande y, debajo, un subtítulo en `.subheadline` gris que a veces es un menú («Ríos Diseño & Obra · Octubre 2026 ▾», «Facturas ▾»). Buscador del sistema. Contenido en grupos de radio 24 con el título del grupo fuera (`SectionHeader`) o encabezado `.footnote` (`SectionLabel`). Filas: título `.body`, subtítulo `.footnote` gris, importe `.body` a la derecha con el estado debajo, chevron del sistema si abre algo. Barra de pestañas de vidrio del sistema.
- **Fichas y detalles.** Botón atrás de vidrio, título pequeño centrado, «⋯» de vidrio con un menú (editar, duplicar, anular). Cifra grande centrada (40 bold) con el estado debajo; acciones en círculos de vidrio (`ProfileAction`) o en baldosas `surface` radio 16; «Registrar pago» como grupo de formulario con segmentado y botón principal dentro; «Actividad» como lista con círculos de 22 pt rellenos de Tinta.
- **Editores (hoja).** Botón «×» de vidrio a la izquierda y «✓» relleno de Tinta a la derecha (en iPhone); formulario agrupado; barra de vidrio flotante abajo con el total y los botones. En el Mac, la hoja con «Cancelar» y la acción por defecto.
- **iPad.** Barra lateral de 300 pt (panel `surface`, filas de 46 pt, la elegida en `brandFill` con texto blanco, grupos «Negocio» y «Libros», subsecciones de la sección activa sangradas, buscador arriba, empresa al pie). Columna de lista de 340 pt dentro de un panel `surface` radio 26, con título grande, contador, buscador, segmentado y filas que se seleccionan en `brandFill`.
- **Mac.** Barra lateral del sistema (fila elegida en `fill2`, iconos en Tinta, grupos en 11 semibold). Barra de la ventana con título de 15 bold y subtítulo de 11, controles de vidrio de 32 pt (periodo, «Gasto | Factura», buscador de 200 pt, inspector). Contenido: cajas de cifras, gráficas y tablas (`TableCard`) con filas de 28 y cebra (`surface`); la fila elegida en `brandFill` con texto blanco. Inspector de 300 pt a la derecha con secciones de filas «etiqueta gris · valor» de 26 pt y botones al pie (principal relleno de Tinta, secundario con borde).

---

## 2. Qué cambia respecto a lo de ahora (resumen)

1. Fondos y texto del sistema en lugar de la paleta propia (`#F4F5F9`, `#12142B`…).
2. Los estados dejan de ser cápsulas de color: punto + texto.
3. Ninguna tarjeta rellena de marca (efectivo, ganancia, total por cobrar): tarjetas normales con la cifra en `label`.
4. El botón principal pasa a estar relleno de Tinta (`.glassProminent`); el secundario, cápsula gris con texto en Tinta.
5. Filtros con el segmentado del sistema o el botón de filtro de la barra, no con chips.
6. Iconos de fila tipo Ajustes (blanco sobre color del sistema) y monogramas grises tipo Contactos.
7. Encabezados en tipo oración; títulos de grupo en `.title3` bold fuera de la tarjeta.

---

## 3. Mapa pantalla → tablero → archivo, por áreas

Cuatro áreas que pueden rehacerse a la vez **sin tocar los mismos archivos**. Reglas comunes:

- **No editar** `DesignSystem/Palette.swift`, `DesignSystem/Components.swift` ni `Sales/SalesWideViews.swift`. Si un área necesita una pieza nueva, la crea `private` en su propio archivo y lo anota para subirla al sistema después.
- Lo de fase 2 que muestran los tableros (escanear con OCR, bandeja por revisar, conciliación, estimados, usuarios, reglas, notificaciones, varias empresas, logotipo) no se implementa (DISEÑO §3, §7.4); la pantalla se compone sin ese hueco.
- Comprobar en claro y oscuro, iPhone, iPad y Mac, con AX5 (las filas pasan a columna).

### Área A · Inicio, Reportes e Impuestos

| Pantalla | Tableros | Archivos | Qué cambia |
|---|---|---|---|
| Inicio iPhone | `Home`, `HomeOscuro` | `Home/HomeView.swift` | Una sola tarjeta de resumen: «Efectivo disponible» (36 bold, punto verde + «3 cuentas · actualizado…») y, tras un separador, Ingresos · Gastos · Ganancia en tres columnas (`KPITile` sin su propia tarjeta). Subtítulo «Empresa · Mes ▾» como menú de periodo. Acciones rápidas con `QuickAction` (Factura · Gasto · Cliente; «Escanear» es fase 2, o «Recibo» = adjuntar foto si se quiere la destacada). Gráfica en tarjeta con segmentado «6 meses · 12 meses» (`FilterPicker`), barras Tinta/naranja y leyenda con puntos. Títulos de grupo fuera con `SectionHeader` («Por cobrar · Ver todo», «Por pagar · 14 días», «Cuentas · Banca»). Por cobrar: total, barra roja/Tinta, filas con estado de texto. Por pagar: `DateTile`. Cuentas: `IconTile` con `Palette.bankAccount` / `.creditCard` (ahorro: `.green`). |
| Inicio vacío | `EstadoVacio`, `MacVacio` | `Home/HomeView.swift` | Símbolo, «Aquí verás cómo va tu negocio», botón `.primaryCompact`; «Primeros pasos · 1 de 4» con barra de progreso y filas con círculo verde o anillo `chevron` |
| Inicio iPad | `iPadInicio`, `iPadInicioOscuro`, `iPadInicioV` | `Home/HomeView.swift` | Mismas piezas en dos columnas, tarjetas radio 24, `KPIGrid` |
| Inicio Mac | `MacInicio` | `Home/HomeView.swift` | Cajas de cifras (`KPIGrid large`), gráfica de 12 meses en caja, «Cuentas · Revisar», tablas «Facturas por cobrar» y «Cuentas por pagar · próximas» con `TableCard` y cebra; periodo y «Gasto · Factura» en la barra. El inspector de la factura elegida es opcional (ver §4) |
| Reportes iPhone | `ReportePyG` | `Reports/ReportsView.swift` | Título «Resultados» + subtítulo; segmentado Mes · Trimestre · Año; tarjeta «Ganancia neta» (`HeroCard` + gráfica Tinta vs. gris del periodo anterior); grupos Ingresos / Gastos con su total en una tarjeta aparte; «Otros reportes» como lista con `IconTile` y chevron, en lugar de los chips de tipo de reporte |
| Reportes iPad | `iPadPyG`, `iPadPyGV` | `Reports/ReportsView.swift` | Igual a dos columnas |
| Reportes Mac | `MacPyG`, `MacBalance`, `MacBalanza`, `MacAntigCobrar`, `MacAntigPagar`, `MacSalesTax` | `Reports/ReportsView.swift` | Tablas `TableCard`, cajas de cifras; la «Total abierto» de antigüedad deja de ir rellena de marca (`onBrand`); `CheckboxStyle` con el `Toggle(.checkbox)` del sistema |
| Impuestos | `Impuestos`, `MacImpuestos` | `Taxes/TaxesView.swift` | Tarjeta «Impuesto sobre ventas por pagar» (`HeroCard`) con `DateTile` «ENE 20 · Declarar y pagar» y botón principal; «Desglose» como grupo de filas; «Tasas de impuesto» como lista con «Nueva tasa» en Tinta y pie gris; interruptor y selector de periodo. Mac: cajas + tabla de tasas. «Gastos deducibles» y «Exportar para mi contador» son fase 2 |

### Área B · Ventas y Clientes

| Pantalla | Tableros | Archivos | Qué cambia |
|---|---|---|---|
| Facturas iPhone | `Ventas` | `Sales/SalesView.swift` | Sin `UnderlineTabs` ni chips: subtítulo «Facturas ▾» como menú de sección (Facturas · Clientes; Estimados, Recibos, Pagos y Productos son fase 2) y `FilterMenu` en la barra junto a «+». Línea «5 facturas · Por cobrar $…» en `.footnote` sobre el grupo. Filas sin monograma (el canvas no lo pone), con chevron |
| Detalle de factura | `FacturaDetalle`, `iPadVentas` (columna derecha) | `Sales/InvoiceDetailView.swift` (**después de integrar el arreglo en curso**) | Cifra centrada de 40 con el estado debajo; baldosas Duplicar · PDF · Recordatorio; «Registrar pago» como grupo con `FilterPicker` Total · Parcial y botón principal dentro; «Actividad» con círculos de Tinta; «⋯» de vidrio con editar/anular |
| Nueva factura | `FacturaNueva`, `MacFacturaNueva` | `Sales/InvoiceEditorView.swift` | Cliente como fila con monograma; Número · Fecha · Términos como filas de formulario; líneas con cantidad en cápsula «− | +»; totales en grupo; «Notas y términos» como fila; barra de vidrio con Total + «Vista previa» (secundario) + «Enviar» (principal). Mac: hoja ancha, mismo contenido, «Cancelar»/«Emitir factura» |
| Vista previa y envío | `FacturaEnviar` | `Sales/InvoicePDF.swift` | Página con sombra sobre el fondo, grupo «Enviar por correo», barra de vidrio con importe + «Enviar». El PDF en sí no cambia (forzado a claro) salvo `Palette.brand` → `logoFill` en «FACTURA» si se quiere el tono fijo |
| Clientes | `Clientes`, `MacClientes` | `Sales/CustomerViews.swift` (`CustomerListView`, `CustomerRow`) | Monograma gris de 40, saldo y estado de texto; «Ningún cliente coincide · Crear cliente» |
| Ficha de cliente | `ClienteFicha`, `MacClienteFicha` | `Sales/CustomerViews.swift` (`CustomerDetailView`) | `ProfileHeader` centrado, cuatro `ProfileAction` (Llamar · Mensaje · Correo · Factura), tarjeta «Saldo pendiente» (28 bold) con barra vencido/por vencer, historial con estado de texto. Mac: cabecera a la izquierda + cajas + tabla «Historial de facturas» + bloque «Contacto» |
| Editor de cliente, reembolso | — | `Sales/CustomerViews.swift` | Formulario agrupado del sistema |
| Productos, Estimado | `Productos`, `Estimado` | — | Fase 2 |

Filas de la columna maestro de Facturas y Clientes (iPad/Mac): están en `Shell/MasterDetail.swift`, del **área D**.

### Área C · Gastos, Proveedores, Por pagar, Banca y Contabilidad

| Pantalla | Tableros | Archivos | Qué cambia |
|---|---|---|---|
| Gastos iPhone | `Gastos` | `Expenses/ExpensesView.swift` (`ExpensesView`, `ExpenseListView`, `ExpenseRow`) | Segmentado Gastos · Por pagar · Recurrentes (`FilterPicker`; Recurrentes es fase 2); «Octubre · Por categoría» con tarjeta «Total del mes» (28 bold), barra apilada por categoría y leyenda en dos columnas; grupo con «Por pagar esta semana» (`IconTile` naranja, «3 facturas» en `warning`) y «Proveedores» (morado); «Recientes · Filtrar»; filas con `IconTile` de categoría y clip si tiene recibo, importe en `ink` |
| Por pagar | `Gastos` (Por pagar), `MacPorPagar` | `Expenses/ExpensesView.swift` (`BillListView`, `BillRow`, `PayBillView`) | Filas con `DateTile`; Mac: tabla con acción «Registrar pago» por fila |
| Nuevo gasto | `MacGastoNuevo`, `ReciboGasto` (sin OCR) | `Expenses/ExpensesView.swift` (`ExpenseEditorView`), `Expenses/ReceiptViews.swift` (**después del arreglo en curso**) | Formulario agrupado; zona de recibo «Arrastra una foto o un PDF» en el Mac; «Guardar y nuevo» |
| Detalle de gasto | `MacGastos` (inspector) | `Expenses/ReceiptViews.swift` (`ExpenseDetailView`) | Filas «etiqueta gris · valor», recibo adjunto |
| Proveedores y ficha | `ProveedorFicha`, `MacProveedores`, `MacProveedorFicha` | `Expenses/ExpensesView.swift` (`VendorListView`, `VendorRow`, `VendorEditorView`), `Expenses/VendorDetailView.swift` | Como la ficha de cliente: `ProfileHeader`, `ProfileAction` (Llamar · Mensaje · Correo · Recibo), resumen de tres cifras en una sola tarjeta con separadores verticales (`MiniStat` sin tarjeta propia) |
| Banca | `BancaCuentas`, `iPadBancaCuentas`, `Banca` (solo cuentas) | `Banking/BankingView.swift` | Cuentas como filas con `IconTile` (azul/verde/índigo) en vez de la tarjeta destacada rellena de marca (`onBrand`); movimientos del mes en tabla (Mac) o lista; «Importar y conciliar · Próximamente» |
| Plan de cuentas, asientos, libro mayor, cierre | `MacPlanCuentas`, `MacDiario`, `MacLibroMayor`, `MacCierre` | `Accounting/AccountingViews.swift` (**después del arreglo en curso**), `Accounting/AccountingWideViews.swift`, `Accounting/LedgerBrowserView.swift` | Tablas `TableCard` con cebra, cabeceras en tipo oración, campos `fieldBox`; cierre con caja «Libros cerrados hasta», lista de revisión con círculos e historial en tabla |

Filas de la columna maestro de Gastos, Proveedores, Por pagar, Banca, Asientos y Plan de cuentas, y `BillDetailView`: en `Shell/MasterDetail.swift`, del **área D**.

### Área D · Estructura (pestañas, barra lateral, maestro-detalle), estados, Alta y Ajustes

| Pantalla | Tableros | Archivos | Qué cambia |
|---|---|---|---|
| Pestañas, «Más», bloqueo | `Mas`, `Main` (barra de pestañas) | `Shell/RootView.swift` (**después del arreglo en curso**) | «Más» como la app Ajustes: fila de la empresa con monograma de 56 y chevron, grupos con encabezado `.footnote` y filas de 44 con `IconTile` de colores, en lugar de las baldosas `MoreTile`. El monograma de la empresa (hoy blanco con texto negro en oscuro) pasa a `Palette.monogram`. Pestañas: ver §4 |
| Barra lateral | `Sidebar` | `Shell/Sidebar.swift` | Grupos «Negocio» (Inicio, Ventas, Gastos, Banca, Reportes) y «Libros» (Contabilidad, Impuestos, Ajustes) en lugar de «MÁS»; iconos en Tinta; iPad: panel `surface` radio 26, título «Chirogra» de 28 bold, filas de 46 con la elegida en `brandFill`; Mac: material del sistema (`Palette.sidebar` ya es transparente), filas de 28 con la elegida en `fill2`; empresa al pie con monograma y «iCloud · hace 2 min» |
| Maestro-detalle | `iPadVentas`, `iPadVentasV`, `iPadBanca` | `Shell/MasterDetail.swift` (**después del arreglo en curso**) | `MasterRow`: dos líneas (nombre + importe / número · vencimiento + estado de texto), la elegida en `brandFill` con todo en blanco (hoy `brandWash`); `MasterFilterBar` con `FilterPicker` (segmentado) o `FilterMenu`; «+ Factura» como botón principal compacto en el iPad. Aquí viven las listas maestro de todas las áreas y `BillDetailView` |
| Estados | `EstadoCargando`, `EstadoError`, `MacCargando`, `MacError` | `Shell/SyncStatusViews.swift` | Cargando: «Sincronizando con iCloud…» con esqueleto de filas en `surface2`; error: tarjeta centrada «No pudimos sincronizar tus datos» con «Reintentar» (principal) y «Seguir sin conexión» (secundario), aviso de «Sin conexión» con fondo `warningWash` |
| Alta | `OnbEmpresa`, `OnbTipo`, `OnbBanco`, `AltaPaso1`, `AltaPaso2`, `iPadAltaPaso1` | `Onboarding/OnboardingView.swift` | Título grande centrado con símbolo; datos como grupos de formulario (`SectionLabel` encima, nota gris debajo); barra de vidrio inferior con los puntos de paso y «Continuar» (`.primary`); tipo de negocio como lista con marca de selección en lugar de chips rellenos (`onBrand`). Logotipo y paso 3 (banco) fuera del MVP |
| Ajustes | `AjustesEmpresa`, `AjustesFormatos`, `AjustesPlantilla`, `AjustesDatos`, `MacAjustes` | `Settings/SettingsView.swift` | Formularios agrupados del sistema; Datos y seguridad como `AjustesDatos` (interruptores con `IconTile`, «Crear copia ahora» en Tinta, exportar con chevron); Mac: `MacAjustes` en columnas con campos `.roundedBorder`. Usuarios y permisos, fase 2 |

---

## 4. Diferencias entre el canvas actual y las decisiones anteriores

Anotadas para que el usuario decida; la base no las resuelve por su cuenta salvo donde se dice.

1. **Botón principal relleno de Tinta.** El canvas rellena los botones principales con el acento (`--tintFill`: «Enviar factura», «Registrar $…», «Continuar», «Guardar» del Mac, «+ Factura» del iPad, «Nueva factura» del Mac). DISEÑO §7.4 decía «Liquid Glass sin relleno de marca». La base usa `.glassProminent` teñido de Tinta: sigue siendo Liquid Glass y es el único relleno, del acento, pero **es relleno**. Para volver a vidrio sin relleno basta cambiar `PrimaryButtonStyle` y `CompactPrimaryButtonStyle` (una línea cada uno). Pendiente de confirmar.
2. **Pestañas del iPhone.** El canvas pone Inicio · Ventas · Gastos · **Banca** · Más (Reportes dentro de Más). El MVP (DISEÑO §7.1) tiene Inicio · Ventas · Gastos · **Reportes** · Más, con Banca en Más porque casi toda es de fase 2. No se ha tocado (`Shell/RootView.swift`).
3. **Mac: tabla + inspector frente a maestro-detalle.** `MacVentas`, `MacGastos`, `MacPorPagar`, `MacInicio`… muestran tabla a todo el ancho con un inspector de 300 pt a la derecha (el título del grupo 7 dice «iPad (maestro-detalle) y Mac (inspector)»). ~~La decisión del usuario es columna maestro también en el Mac.~~ **Cambiada el 2-nov:** en el Mac, tabla + inspector como el canvas; el iPad sigue con maestro-detalle (ver §5).
4. **Selección de la columna maestro.** El canvas (iPad) la pinta en `brandFill` con texto blanco; hoy va en `brandWash` (decisión de contraste AA de `281d573`). Blanco sobre `#3A3FD1` / `#5458E6` da 7,5:1 / 5,4:1, así que cumple AA. Lo cambia el área D si el usuario está de acuerdo.
5. **Ícono de la app.** El canvas dibuja el ícono (Tinta, «C» blanca, punto azafrán) en `Main`. Se mantiene el de Icon Composer (decisión del usuario); el dibujo del canvas queda como `LogoMark` dentro de la app.
6. **Densidad del Mac.** El canvas usa filas de 28, botones de 28 y cabeceras de 26: coincide con `Metrics.target` de 28. Sin conflicto.
7. **«¿Descartar los cambios?»** El canvas no lo muestra; no lo contradice. Se conserva.
8. **Barra lateral.** El canvas agrupa «Negocio» / «Libros»; hoy es «MÁS». No es una decisión del usuario, solo un cambio del canvas (área D).
9. **Modo oscuro del Mac.** Aplazado por el usuario; los tokens ya tienen variante oscura igualmente (`MacVentasOscuro`).

## Decisiones del usuario sobre las contradicciones (2-nov-2026)

1. **Botón principal: vidrio sin relleno de marca** (no como el canvas). `PrimaryButtonStyle` y `CompactPrimaryButtonStyle` usan `.glass` con el texto en `ink`.
2. **Pestañas del iPhone: como el canvas** — Inicio · Ventas · Gastos · **Banca** · Más. Reportes pasa a «Más». (Área D.)
3. **Fila elegida en la columna maestro (iPad y Mac): rellena de Tinta con texto blanco**, como el canvas. (Área D.)
4. **Barra lateral: grupos «Negocio» y «Libros»**, como el canvas, en lugar de «MÁS». (Área D.)
5. **Mac: tabla + inspector (2-nov)**, como el canvas; el iPad sigue con maestro-detalle. Sustituye a «maestro-detalle en iPad y Mac». Ver §5.

---

## 5. Mac: tabla + inspector

En el Mac, las páginas de lista (`MasterPage`: Facturas, Clientes, Gastos, Proveedores, Por pagar, Banca, Asientos, Plan de cuentas) son **barra lateral + contenido** (dos columnas): el contenido es una `Table` del sistema a todo el ancho y, a la derecha, el **inspector nativo** (`.inspector(isPresented:)`, ~300 pt, `inspectorColumnWidth(min: 260, ideal: 300, max: 420)`) con lo elegido. Elegir una fila abre el inspector; el botón `sidebar.trailing` de la barra o **⌥⌘I** lo muestra u oculta (se recuerda en `@AppStorage("macInspectorShown")`). Doble clic (o «Abrir» del menú contextual) abre la ficha completa encima, en la pila de la columna. El iPad no cambia: columna maestro + detalle de `Shell/MasterDetail.swift`.

### Cómo está montado (no hace falta tocarlo)

- `Shell/RootView.swift` (`AppShell.columns`): en macOS, si la página tiene tabla (`page.hasMacTable`), `NavigationSplitView` de dos columnas con `detailColumn { page.macTable(selection: $masterSelection) }`; si no, las tres columnas de antes. Se conservan el aviso «¿Descartar los cambios?» al cambiar de página, la búsqueda de la barra lateral (con texto, `SearchResultsView` sustituye a la tabla), la barra lateral de 220 pt y el arreglo del iPad en vertical (todo lo nuevo va bajo `#if os(macOS)`).
- `Shell/MacTablePage.swift`: el `switch` de `MasterPage.hasMacTable` y `macTable(selection:)`, que llaman a **un tipo por página en su propio archivo**, y la pieza común:
  - `MacTablePage` — título y subtítulo de la ventana (`navigationSubtitle`), búsqueda (`.searchable(placement: .toolbar)`), «+ Nuevo…» y el botón del inspector en la barra; arriba del contenido el filtro, las cajas de cifras (`KPIGrid`) si hay, la tabla con columnas ordenables y cebra, el pie con la cuenta y el estado vacío («Sin resultados · Quitar filtros»); el inspector con su título (15 bold), el contenido con scroll y los botones al pie.
  - `MacTableFilter` — segmentado del sistema con la cuenta de cada opción («Todas 14 · Borrador 1…»); si no cabe, menú (así no fija el ancho mínimo de la ventana).
  - `MacInspectorSummary` (nombre, cifra de 24 y estado), `MacInspectorSection` («Detalles», «Importes»: encabezado de 11 semibold y filas con línea entre ellas), `MacInspectorRow` («etiqueta gris · valor», 26 pt; con `value:` de texto o un `@ViewBuilder`).
  - `MacCellText`, `MacCellStatus` — texto de color y estado («● Vencida · 8 días») de una celda que pasan a blanco en la fila elegida (`backgroundProminence == .increased`). Para el gris normal basta `.foregroundStyle(.secondary)`.

### Qué archivo toca cada página

Cada página ya tiene su archivo con un esqueleto (`static let isReady = false`, `@Binding var selection: UUID?`, `body` vacío). Para hacerla: escribir el `body` con `MacTablePage` y poner `isReady = true`. **Nada más**: ni `RootView.swift`, ni `MacTablePage.swift`, ni `MasterDetail.swift`.

| Página | Tablero | Archivo (solo este) | Inspector: qué reutilizar |
|---|---|---|---|
| Facturas | `MacVentas`, `MacVentasOscuro` | `Sales/InvoiceTablePage.swift` (**hecha**) | — |
| Clientes | `MacClientes` | `Sales/CustomerTablePage.swift` | Saldo, contacto; «Abrir» → `CustomerDetailView` |
| Gastos | `MacGastos` | `Expenses/ExpenseTablePage.swift` | Lo de `ExpenseDetailView` (`ReceiptViews.swift`) en filas, recibo |
| Proveedores | `MacProveedores` | `Expenses/VendorTablePage.swift` | «Abrir» → `VendorDetailView` |
| Por pagar | `MacPorPagar` | `Expenses/BillTablePage.swift` | «Registrar pago…» → `PayBillView`; «Abrir» → `BillDetailView` |
| Banca | `BancaCuentas` | `Banking/BankingTablePage.swift` | Cuentas en la tabla; movimientos (`AccountMovementsView`) o saldo en el inspector |
| Asientos | `MacDiario` | `Accounting/JournalTablePage.swift` | Líneas del asiento; «Abrir» → `JournalEntryDetailView` |
| Plan de cuentas | `MacPlanCuentas` | `Accounting/ChartTablePage.swift` | Saldo y tipo; «Abrir» → `LedgerView(account:inDetailColumn: true)` |

Los filtros, las consultas y los textos de las listas maestro están en `Shell/MasterDetail.swift` (`BillFilter`, `VendorFilter`, `InvoiceScope`…): se pueden reutilizar, pero ese archivo no se toca. Las piezas que una página necesite y no estén en `MacTablePage.swift` se crean `private` en su archivo y se anotan para subirlas después.

### Ejemplo (resumen de `Sales/InvoiceTablePage.swift`)

```swift
#if os(macOS)
struct InvoiceTablePage: View {
    static let isReady = true
    @Binding var selection: UUID?
    @Query(sort: \Invoice.createdAt, order: .reverse) private var invoices: [Invoice]
    @State private var filter: InvoiceListView.Filter = .all
    @State private var query = ""
    @State private var openedInvoice: Invoice?

    var body: some View {
        MacTablePage(
            title: String(localized: "Facturas"), subtitle: String(localized: "Ventas · \(invoices.count) facturas"),
            rows: filtered, footer: footer, query: $query, searchPrompt: Text("Cliente, número o monto"),
            selection: $selection, sortOrder: [KeyPathComparator(\Invoice.tableNumber, order: .reverse)],
            kpis: kpis, addTitle: String(localized: "Nueva factura"), onAdd: { creating = true },
            onOpen: { openedInvoice = $0 }, empty: …, inspectorTitle: { … }, inspectorPlaceholder: …
        ) {
            TableColumn("Número", value: \.tableNumber) { MacCellText(text: $0.number) }.width(min: 56, ideal: 64, max: 110)
            TableColumn("Estado", value: \.statusRank) { MacCellStatus(chip: $0.tableStatus) }
            TableColumn("Importe", value: \.tableAmount) { Text($0.tableAmount.money).monospacedDigit() }.alignment(.trailing)
        } filter: {
            MacTableFilter(title: …, options: InvoiceListView.Filter.allCases, selection: $filter, label: \.localizedTitle) { … }
        } inspector: { invoice in
            MacInspectorSummary(…) { invoice.tableStatus }
            MacInspectorSection(title: String(localized: "Detalles")) { MacInspectorRow(String(localized: "Número"), value: invoice.number) }
        } actions: { invoice in
            Button("Registrar pago…") { paying = invoice }.buttonStyle(.primary)
            HStack { Button("Abrir factura") { openedInvoice = invoice }.buttonStyle(.secondary) }
        }
        .navigationDestination(item: $openedInvoice) { InvoiceDetailView(invoice: $0) }
    }
}
#endif
```

Detalles que conviene saber:

- **Claves de orden `nonisolated`.** El módulo es `@MainActor` por defecto y `KeyPathComparator` exige key paths `Sendable`: las propiedades calculadas que se usan como `value:` de una columna van en una extensión del modelo marcadas `nonisolated` (`Invoice.tableNumber`, `tableAmount`, `statusRank`, `customerName`). Las del modelo (`issueDate`, `dueDate`) ya sirven.
- **Anchos.** Mínimos e ideales modestos (la suma de ideales por debajo de ~600 pt): con la ventana de 1280 y el inspector abierto, el contenido mide ~720 pt; si los ideales no caben, la tabla se desplaza a lo ancho.
- **Filtrar en la página, ordenar en la pieza.** `rows` llega ya filtrado por la búsqueda y el filtro; `MacTablePage` lo ordena con el orden de las columnas.
- **Botones del inspector:** principal `.buttonStyle(.primary)` (vidrio sin relleno, decisión del usuario), secundarios `.buttonStyle(.secondary)` (borde del sistema). Hojas con `NavigationStack { … }.editorSheetSizing()` y `.discardableEditor(…)` para «Cancelar».
- **Textos nuevos** en `App/Localizable.xcstrings` con su inglés (los archivos son solo de macOS: `scripts/sync-strings.sh` compila para iOS y no los ve; añadirlos a mano o con los `.stringsdata` de una compilación del Mac).

### Comprobar en el Mac sin tocar la app del usuario

Copia de prueba con otro identificador (su propio contenedor, sin iCloud) y argumentos de QA (solo Debug, `QALaunch` en `MacTablePage.swift`):

```bash
xcodebuild -project Chirogra.xcodeproj -scheme Chirogra -configuration Debug -destination 'platform=macOS' -derivedDataPath .dd \
  PRODUCT_BUNDLE_IDENTIFIER=com.chirogra.qa.mac CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
open -g -j -n .dd/Build/Products/Debug/Chirogra.app --args -AppleLanguages '(es)' \
  -qa.muestra 1 -qa.seccion invoices -qa.fila 0 -qa.inspector 1 -qa.apariencia oscuro
```

- `-qa.seccion` `home|invoices|estimates|customers|expenses|vendors|bills|banking|journal|chart|ledger|close|reports|taxes|settings`; `-qa.fila N` elige la fila N (en el orden de la tabla); `-qa.inspector 0|1`; `-qa.muestra 1` carga los datos de ejemplo si no hay empresa; `-qa.apariencia claro|oscuro` (en el Mac, `-AppleInterfaceStyle Dark` como argumento no cambia la apariencia).
- Solo Facturas: `-qa.pago 1` abre «Registrar pago…», `-qa.registrar 1` además lo registra; `-qa.abrir 1` abre la factura completa.
- Build 4 (la app se explica sola): `-qa.vacia 1` crea una empresa nueva y vacía («Taller Luna») sin pasar por el alta (estados vacíos); `-qa.pistas reset|todas|ocultas` (TipKit; con otros `-qa.*` y sin este, las pistas no salen); `-qa.asiento aportacion|retiro|traspaso|manual` abre el editor de asientos con esa plantilla y $500 (con `-qa.nuevo 1` en Asientos del Mac); `-qa.ayuda debitoCredito|gravable|capital|combinada|saldo` abre ese ⓘ (en el Mac, con la ventana oculta de `open -j`, el globo no sale); `-qa.tasaNueva 1` abre «Añadir tasa…» en una factura nueva si no hay tasas.
- Alta (para las capturas de la guía web): `-qa.alta 1|2|3`, `-qa.altaEstado TX`, `-qa.altaCiudad Austin -qa.altaCiudadTasa 2`, `-qa.altaBanco 1250000 -qa.altaTarjeta 30000` (centavos), `-qa.altaCrear 1`. Para una ventana de otro tamaño: `-"NSWindow Frame SwiftUI.WindowGroup<ChirograUI.ChirograRootView>-1-AppWindow-1" "x y ancho alto 0 0 <pantalla>"`.
- Captura solo de esa ventana con `screencapture -l <id> -o -x`, sacando el id con `CGWindowListCopyWindowInfo` filtrado por su PID; al terminar, `kill <pid>`. La ventana queda inactiva (oculta y en segundo plano): la fila elegida sale en gris y los botones de vidrio atenuados; activa, la fila va en Tinta.
