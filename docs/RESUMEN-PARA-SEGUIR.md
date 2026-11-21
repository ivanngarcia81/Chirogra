# Chirogra: resumen para empezar el siguiente chat (21-nov-2026, build 59)

Lee esto primero y después [CONTEXTO.md](CONTEXTO.md), que tiene el detalle («Dónde nos quedamos» y «Siguiente»).
**Al usuario se le habla siempre en español.**

## Estado

- **Ramas:** `version-1.3` empujada el 21-nov hasta el build 58 y su resumen; el build 59 (`34f6cc0`) y sus docs
  (`22f7428`), empujados el 21-nov. `main` en `83b1db4` (build 50 y la
  web con «Kairogra»), empujada el 17-nov; los builds de después no tocan la web, así que `main` no hace falta moverla.
  La web (`sitio/`) se publica desde `main`.
- **Último build: 59 (1.3.0)**, subido a TestFlight para iOS y macOS el 21-nov (`34f6cc0`): anular un cobro. Antes: 58 (21-nov), 57 (21-nov), 56 (21-nov), 55 (20-nov), 54 (20-nov), 53 (18-nov), 52 (18-nov), 51
  (recorrido de la primera vez, 17-nov) y 50 (17-nov). Los testers externos (Userbrain, Beta Family) entran con el enlace público
  https://testflight.apple.com/join/RGwqqUyw: **el usuario tiene que asignar el 58 a ese grupo** cuando Apple lo procese.
- **En App Store Connect:** la **1.0 (build 11)** espera la revisión. **Decidido el 13-nov:** cuando la aprueben se envía
  **directo la 1.3** con su último build, sin la 1.0.1, la 1.1 ni la 1.2, con un «What's New» que junte las tres. El plan
  «Chirogra para contadores» está completo en App Store Connect y va en ese envío (no pulsar «Add for Review» suelto).
  El 17-nov la web de App Store Connect le fallaba al usuario (sin apps, «News Request», lo sacaba al entrar); la página
  de estado de Apple no marcaba nada y las subidas funcionaban: era la sesión de Safari (pestaña privada / borrar datos).
- **Aparatos del usuario:** iPhone y Mac con el código del 45 instalado desde Xcode; desde entonces prueba con TestFlight.
  El iPad, desde TestFlight cuando quiera (no insistir).
- **Plan de la 1.4** (agenda + asistente con Claude) en [PLAN-1.4.md](PLAN-1.4.md); **plan de la 2.0** en
  [PLAN-2.0.md](PLAN-2.0.md).

| Build | Commit | Qué trae |
|---|---|---|
| 22 | `3662619` | Bienvenida en carrusel animado (opción B del canvas «Chirogra — Bienvenida»). |
| 23 | `5473946` | Panel de clientes del plan para contadores (canvas del usuario «Chirogra — Panel de clientes», encargo en [PANEL-CLIENTES.md](PANEL-CLIENTES.md)). |
| 24 | `d7c2e0a` | «Reclasificar gastos…» en lote; tasa al cambiar de estado en Ajustes; errores del alta visibles; aviso 1099 del Mac; Puerto Rico 10.5 % comprobado. |
| 25 | `f23f5a7` | Arreglos de la QA con tres agentes (iPhone, iPad y copia del Mac): «+» de Inicio en solo lectura, gráfica de Inicio, «Por cobrar» filtrado, ventana del Mac, panel, textos y plurales. |
| 26 | `eccaaa9` | Tarjeta del mes de Gastos con la base de Inicio (decisión del 10-nov, cambia la del 2-nov), letra grande, tasas en orden estable, signo «−», «Seguridad» en Más. |
| 27 | `7095e90` | «With receipt» en el filtro de Gastos en inglés (faltaba en el catálogo) y prueba que exige en el catálogo las etiquetas de los enums. |
| 28 | `b379921` | Panel de clientes: fila elegida legible (blanco sobre Tinta) y columnas Sales tax, Avisos y Última actividad sin cortar. |
| 29 | `713ecd2` | Con la app en inglés, la empresa de ejemplo sale en inglés («Rios Design & Build»), también con la región en español. |
| 30 | `e56f45c` | Tarjeta de deducibles de Impuestos: «Export for My Accountant…» ya no se parte en tres líneas (iPad) ni se corta (Mac); si no caben, los botones van uno debajo del otro. **Último de la 1.1.** |
| 31 | `b4d04c5` | **Versión 1.2.0** (rama `version-1.2`): ajustes del contador, bitácora de cambios, Dividir y motivo al excluir. Esquema 5 desplegado y probado en Producción. |
| 32 | `0b4137d` | 1.2.0: la última página de la bienvenida pregunta «¿Para quién llevas los libros?»; camino del contador (canvas «Chirogra — Contadores», opción A). |
| 33 | `87e7a39` | 1.2.0: arreglos de la QA con tres agentes (11-nov): campos de Banca que no tomaban el toque (`labeledField` con el estilo del sistema), Dividir con cuenta e importe en filas separadas, filtro «Del contador» en el diario del iPhone y el iPad, bitácora con fechas «5 nov 2026», «−$» y estados de estimado en palabras, textos de Excluir y del alta del contador, letra grande en la bienvenida. |
| 34 | `e802c4b` | 1.2.0: «Saltar» de la bienvenida del iPhone y el iPad en cápsula de vidrio (el usuario no lo veía como texto suelto). |
| 35 | `a89b78f` | 1.2.0: «Ocultar» / «Mostrar» en los «Primeros pasos» de Inicio también sin movimientos (`homeSetupStepsHidden`, por aparato). |
| 36 | `3e50675` | 1.2.0: **sales tax por código postal dentro de la app**: 27,583 ZIP en 34 estados (24 con tasa de condado y ciudad, 10 solo con la del estado). Se sugiere en el alta, en Ajustes y en el cliente. `scripts/tasas/`, DATOS-V5.md. |
| 37 | `e002ed1` | 1.2.0: filas con campo que toman el toque en toda la fila (`.fieldRow()`: descuento, Enviar, presupuesto, plantillas, monto parcial); títulos en los importes de reembolso, nota de crédito y pago de sales tax; «Base: …» en menú con letra de accesibilidad. |
| 38 | `6616919` | 1.2.0: **arreglos de la QA de Hudson** (prueba completa como empresario, contador y auditor; informe en el worktree `Chirogra-QA-Hudson`, carpeta `QA/` sin seguimiento): cierre con motivo obligatorio sin contraseña, «Registrar con fecha» del primer día abierto, «Fijar contraseña y cerrar», «Libros cerrados hasta…» en Inicio, aviso bajo las fechas cerradas y «Cambios después del cierre» (pantalla y paquete del contador); reclasificar lo conciliado sin romper la conciliación; impuesto incluido en $0; fecha al convertir estimado; vencimiento de proveedor; «Saldada: cobrado + crédito»; Total y Saldo en el Mac; alta sin tipo de negocio elegido; guía al día. 330 pruebas; 22/22 controles de Hudson. |
| 39 | `afeb040` | 1.2.0: **pestañas y favoritos a elección en el iPhone** (decisión del usuario del 12-nov): «Más › Personalizar» › Pestañas (entre Inicio y Más, fijos, caben 3 herramientas a elección y en orden) y Favoritos (arriba de Más, sin límite); mantener pulsada una herramienta de Más la añade. Por aparato (`phone.tabs`, `more.favorites`). `Shell/PhoneShortcuts.swift`, guía es/en, `PhoneShortcutsTests` (335 pruebas). |
| 40 | `a2fe01e` | 1.2.0: **Seguridad aparte de iCloud y copias** (pedido del usuario: las dos filas de Más abrían la misma pantalla) y el resto de la QA de Hudson: «Mover dinero» (traspaso, pagar la tarjeta, retiro y aportación) en el «+» de Inicio y en cada cuenta de Banca; ficha de la cuenta con «Entró / Salió»; «Máximo $X (saldo pendiente)» al cobrar; «N ya importados · M nuevos» al reimportar; el ZIP del alta propone el estado; bitácora «Categoría: A → B»; factura con cobros con «Editar» y «Anular» desactivados y el motivo. 338 pruebas. |
| 41 | `ae9ced3` | 1.2.0: **icono nuevo, la χ cursiva** (archivo del usuario «chirogra greek inicials.icon»), también en `LogoMark` (`ChiGlyph`, sacado del SVG), en la animación de la bienvenida (contorno y luego relleno) y en la web. |
| 42 | `36c85ad` | 1.2.0: **lo borrado no vuelve de iCloud**: cada empresa borrada se apunta en el almacén de clave-valor de iCloud (`DeletedCompanies`, permiso `ubiquity-kvstore-identifier` nuevo) y todos los aparatos la vuelven a borrar si alguien la sube otra vez; las automatizaciones esperan a la importación al abrir; **«Borrar todo y empezar de cero…»** en Ajustes › iCloud y copias (escribir BORRAR; espera a que el borrado suba). 343 pruebas. |
| 43 | `809bb88` | 1.2.0: **iconos de color en las subsecciones de la barra lateral** (Mac e iPad; decisión del usuario del 13-nov) y **hoja de planes del Mac** sin los botones de StoreKit encima del segundo plan («Restaurar compras» y «Canjear código» como enlaces, 760 de alto). |
| 44 | `7825510`…`79e8272` | **1.3.0** (rama `version-1.3`): H04 (flechas de periodo en los reportes del iPhone), H19 (antigüedad y conciliaciones en el paquete del contador) y H22 (etiquetas de VoiceOver). |
| 45 | `55add7e` | 1.3.0: icono χρ (χ blanca, ρ azafrán) en la app, la bienvenida y la web. |
| 46 | `786f6fa` | 1.3.0: la tabla de Clientes del iPad ya no pinta su fondo blanco (`.scrollContentBackground(.hidden)`): va sobre el gris de la pantalla y se distingue de la barra lateral (pedido del 15-nov). |
| 47 | `1f96a17` | 1.3.0: **el alta ya no se vacía al salir y volver a la app** (test de Userbrain): `RootView` solo enseña la pantalla de espera de iCloud en la primera importación (`sync.isFirstImport`, antes `isSyncing`, que volvía a ser cierto cada vez que la app volvía al primer plano). |
| 48 | `f99bd71` | 1.3.0: tras el 2.º test de Userbrain: en la factura del iPhone el **precio en su propia fila** (campo con borde) y tocar «Total de la línea» lleva al precio; **«Guardar borrador» con texto** en vez del ✓; **Inicio con cifras en color** (ingresos verde, gastos rojo, ganancia color de marca o rojo si es negativa; también la gráfica y el Mac), «Ganancia del mes» / «Profit this month» y «Sales tax you owe». 346 pruebas. |
| 49 | `292f269` | 1.3.0: arreglos de los testers de Userbrain: 7 días de uso libre, confirmación de factura de $0, «Para guardar, falta: …», franja de iCloud con 20 s de gracia, pista para personalizar la barra, «Se pronuncia «Kairogra»». 346 pruebas. |
| 50 | `9f32335` | 1.3.0: aviso de iCloud en una línea con «×» (sin cuenta, nota azul que no vuelve; «Detalles» con el código), «Marcar como pagada · $X», botón «Precio» en la barra del teclado, «Registrar gasto» en la ficha de la cuenta, «Por cobrar» en grande. 346 pruebas. |
| 51 | `4d84399` | 1.3.0: recorrido de la primera vez en cada pestaña del iPhone (estilo A «Foco» de Claude Design), «Ver el recorrido otra vez» en Más › Ayuda; fuera la pista de personalizar la barra. 346 pruebas. |
| 52 | `5643a27` | 1.3.0: tras un tester de Beta Family: al borrar los datos de ejemplo el recorrido vuelve a salir con la empresa propia; «Sin cuenta ni contraseña: tus libros se quedan en tus aparatos y en tu iCloud.» en la última página de la bienvenida. 346 pruebas. |
| 53 | `a5f6468` | 1.3.0: tras Yurii S. (tester de pago de Beta Family; iPhone 16e, iOS 26.7.1, letra XL, región de Ucrania, oscuro): en Ventas, si «1 570,00 US$ of 2 570 US$» no cabe junto al cliente, «of …» baja a su línea (salía «M…»); «Ver el recorrido otra vez» lleva a Inicio; defensa del hueco del teclado sin teclado (`ignoringStaleKeyboardSpace`; lista cortada y barra de Total a media pantalla, no reproducido). 346 pruebas. |
| 54 | `801e8c3` | 1.3.0: **«Tutorial completo»** en Más › Ayuda (cada pantalla del iPhone explica todos sus botones la primera vez; el corto no cambia); **iOS 27**: los pasos que iluminan botones de la barra de arriba ya no se saltan (`marcoEnVentana` mira `accessibilityElements`); en Inicio el recorrido ilumina el título del grupo con su tarjeta (iPhone 13 mini, Jiga T. de Beta Family). 177 + 75 pruebas. |
| 55 | `216d429` | 1.3.0: tras Yurii S. (Beta Family, build 54; iPhone 16e, formato de Ucrania, oscuro): **campos de dinero** que se editan sin la moneda (`MoneyField`: «10,99» al escribir, «10,99 US$» al salir; antes lo tecleado se pegaba tras «US$» y el importe no cambiaba: «10,99 US$80», «1,00 US$896253»; en EE. UU. «$510.99»); lee coma o punto decimal; **difuminado** (`.ultraThinMaterial`) en la primera tarjeta de cada recorrido, la que no ilumina nada. 177 + 75 + 87 pruebas (`ScreenSmokeTests` ya se caía en el 54: `ImageRenderer`, «no current update to enqueue action to»). |
| 56 | `130588b` | 1.3.0: tras Eric (Beta Family, build 55; iPhone 13, iOS 27.2.1; app 3/5, recomendación 2/5) y un **repaso visual** de toda la app. Ver «Lo siguiente» 0b. 350 pruebas (94 + 181 + 75). |
| 57 | `c13f955` | 1.3.0: en «Nuevo gasto › Recibo» los tres botones (escanear, foto, archivo) vuelven a ir **uno por fila**; salían amontonados en una sola (captura del usuario con el 56; venía del 54). Ver «Lo siguiente» 0a. 350 pruebas. |
| 59 | `34f6cc0` | 1.3.0: **anular un cobro** (pendiente del informe de Eric): cada cobro en su fila de «Actividad» de la factura; tocarlo o «⋯ › Anular cobro…» lo revierte en su fecha, la factura vuelve a quedar pendiente y el movimiento del banco enlazado vuelve a «Por revisar». Ver «Lo siguiente» 0. 355 pruebas. |
| 58 | `944e0ad` | 1.3.0: **Clientes** sin avisos encimados (con un filtro vacío, «Nothing to handle» se montaba sobre «¿Llevas los libros de otro negocio?»; captura del usuario) y **«Idioma»** en Más › Moneda y formatos lleva a Ajustes › Apps › Chirogra. Ver «Lo siguiente» 0. 350 pruebas. |

## Último chat (21-nov): builds 56, 57, 58 y 59

- **Build 59 (`34f6cc0`), en otro chat del mismo día:** el usuario eligió hacer «Anular cobro», el pendiente que quedaba
  del informe de Eric. Visto en el simulador (hoja de capturas mandada) y subido a petición suya. «Lo siguiente» 0.

- **Build 56 (`130588b`):** informe de Beta Family de **Eric** con el 55 (recomendación 2/5: «no security assurances»,
  «parece hecho con IA») y un **repaso visual** de toda la app. Hecho con **un agente por arreglo** en worktrees.
  El usuario vio capturas antes/después de cada cambio de diseño y eligió **mantener el círculo de iniciales** en las
  fichas de cliente y proveedor. Detalle en «Lo siguiente» 0b.
- **Build 57 (`c13f955`):** captura del usuario con el 56: los botones del recibo de «Nuevo gasto» salían amontonados
  en una fila. Venía del 54 (`.id` del tutorial sobre el grupo de botones). «Lo siguiente» 0a.
- **Build 58 (`944e0ad`):** otra captura suya: en Clientes, con un filtro vacío, dos avisos se pisaban. Y preguntó
  **dónde se cambia el idioma**: no se encontraba. Ahora la fila «Idioma» de Más › Moneda y formatos lleva a Ajustes.
  Antes de subirlo pidió **instalar el Debug en su iPhone** para verlo (iPhone 17 Pro Max, `00008150-0005793E3EC0401C`,
  con `devicectl` e iCloud de Producción, ver CONTEXTO «Instalar en los aparatos»). «Lo siguiente» 0.
- **Cómo se trabajó:** capturas en el simulador «Chirogra QA 16e» (`44631678`) con pruebas de interfaz `UITestsQA` en
  una copia aparte (no se commitean: `Build56QA`, `Build56Repaso`, `Build56Cabeceras`, `Build56Circulo`,
  `Build56Menores`, `Build56Recibo`, `Build57Clientes`, `Build58Idioma`). Hojas de capturas antes/después mandadas al
  usuario. El usuario manda capturas de su iPhone con lo que ve mal rodeado: arreglar, enseñar antes/después y
  esperar su «sí» para el build.
- **Worktrees de agentes:** nacen de `main` (`83b1db4`), no de `version-1.3`. Al agente: `git merge --ff-only <HEAD>` y
  `git apply --index <parche de lo sin commitear>`; recoger con `git add -N . && git diff --binary` y aplicar con
  `git apply --3way` (antes `git add -u` si hay cambios sin preparar). Sus DerivedData (~1,5 GB cada uno) llenaron el
  disco: borrarlos al terminar. Los 12 worktrees y sus ramas `worktree-agent-*` ya se borraron.
- **Pruebas:** `swift test --skip ScreenSmokeTests` (94 + 181 + 75 = 350). `ScreenSmokeTests` se cae desde el 54.
  `ReceiptReaderTests` (Vision) falla a veces con el Mac cargado (simuladores, compilaciones); sola pasa.

## Chat anterior (17 y 18-nov): builds 50, 51 y 52, recorrido y testers

- **Builds subidos (iOS y macOS):** 50 (`9f32335`, aviso de iCloud, cobro, precio), 51 (`4d84399`, recorrido de la
  primera vez en cada pestaña del iPhone, estilo A «Foco» de Claude Design) y 52 (`5643a27`, tras un tester de Beta
  Family). Detalle de cada uno en «Lo siguiente», puntos 0, 0a y 0b. 346 pruebas en todos.
- **Build 52:** al borrar los datos de ejemplo se olvidan los recorridos vistos (el tester vio el recorrido con la
  empresa inventada y pedía «el tutorial para mi propio negocio»); y en la última página de la bienvenida, «Sin cuenta
  ni contraseña: tus libros se quedan en tus aparatos y en tu iCloud.» (pedía «entrar con Apple o Google o como
  invitado»: no sabía que no hay cuenta; «como invitado» ya es «Probar con datos de ejemplo»).
- **Testers:** Userbrain (graban la pantalla y hablan), **Beta Family** (formulario con «About the app» y «What to
  test»; tarea del 52 en inglés y español con 3 tareas y 5 preguntas) y **UXtweak** (solo imágenes: se recomendó
  *First Click Test*, sin moderar, con 6 tareas sobre las capturas `01-inicio`, `02-ventas`, `03-gastos` de la tienda,
  copiadas a `~/Desktop/Chirogra-UXtweak`). Los comentarios de errores llegan por «Compartir comentarios beta» de
  TestFlight (captura → miniatura) y se leen en App Store Connect › TestFlight › Comentarios.
- **Redes:** se le dieron textos para invitar a probar con el enlace de TestFlight (Instagram/Facebook, X/Threads e
  inglés) y el logo a 1024 px en `~/Desktop/Chirogra-logo` (redondeado con fondo transparente y cuadrado para perfil,
  sacados de `App/AppIcon.icon/Assets/chirogra-N-icono.svg`).
- **Balance de los testers (pregunta del usuario):** del 47 al 52 casi todo salió de ellos: el alta que se vaciaba
  (fallo real), el error de iCloud sin cuenta, la suscripción que asustaba (3 de 3), el precio de la factura, la factura
  de $0, la pronunciación y el recorrido en la empresa propia. Límites: pocos (unos 6 + 1), casi todo primera impresión
  y no siempre dueños de negocio. Recomendado: esperar lo que digan del 52 antes de más cambios y buscar 2 o 3 negocios
  reales que la usen unas semanas.
- **Ojo al subir:** `xcodegen` quita `com.apple.developer.ubiquity-kvstore-identifier` de `App/Chirogra.entitlements`
  (no está en `project.yml`). En el clon de subida, después de `xcodegen`, `git checkout App/Chirogra.entitlements`, o
  los recorridos vistos no se guardan en iCloud.

## Chats anteriores (16-nov, tarde): testers de Userbrain y builds 47 y 48

- **Testers externos:** el usuario usa **Userbrain** (testers pagados que graban la pantalla y hablan) y TestFlight
  externo con enlace público (lo crea él en App Store Connect). Se le dieron el texto de «What to Test», una tarea
  única para Userbrain y la frase del paso 1 («A simple bookkeeping app for US small businesses to track sales,
  expenses, invoices, and sales tax on iPhone, iPad, and Mac.»).
- **Dos tests vistos (los dos con el build 34).** En el resumen de Userbrain son CS (1.º) y TH (2.º):
  - El alta se vaciaba al salir de la app → **arreglado en el 47** (solo se ve con iCloud real: comprobarlo en TestFlight).
  - La hoja de suscripción asustó al 1.º («It's trying to charge me»), que abandonó. El 2.º siguió tras leer «You will
    not be charged» porque la tarea de Userbrain ya lo explicaba.
  - No encontraba dónde poner el precio de la factura; creía que no se podía guardar sin enviar; calculaba la ganancia
    restando en Banca → **arreglado en el 48** (opción C elegida por el usuario tras ver capturas; la variante de
    recuadros grandes descartada).
  - Pidió asteriscos en los campos obligatorios → **decidido no ponerlos por ahora**: la app ya marca «Opcional». Si
    más testers se pierden, una línea «Falta: …» bajo Continuar.
  - Otros del resumen de Userbrain sin cambio: tipos de negocio que no encajan con algunos sectores (un solo
    comentario) y datos inventados en el alta (normal en un test).
- **Pendientes de decisión del usuario:** si la suscripción deja usar la app un tiempo antes de pedirla (hoy sale al
  crear la empresa, con prueba de 14 días).

## Chat anterior (16-nov, mañana): auditoría y limpieza con 5 agentes

- Pedido del usuario: quitar código muerto, duplicados, archivos y recursos sin uso **sin cambiar nada de lo que hace
  la app**. Cinco agentes en worktrees (Core+Data; tres de ChirograUI por carpetas; recursos/docs/scripts), un revisor
  independiente del diff y unificaciones entre carpetas del coordinador. Rama `limpieza-auditoria`, unida a
  `version-1.3` y `main` (sin build nuevo: lo de la 1.3 ya subido es el 46).
- Quitado: 170 textos del catálogo sin uso (las otras 271 «stale» son textos solo del Mac, **no borrarlas**:
  `sync-strings.sh` solo compila iOS), `scripts/sales-tax-zip.py` (lo sustituyó `scripts/tasas/`), componentes y
  colores sin uso (`FilterChip`, `UnderlineTabs`, `MiniStat`, `HeroCard`, `FlowLayout`, `onBrand`, `outflow`…),
  `Company.shownName` (= `Company.name`), `StatusChip.background` (no se dibujaba). Unificados: `failureAlert`,
  `receiptFileImporter`, `receiptRemovalDialog`, `BillSummarySection`, `BillFilter.matches`, ayudantes de Reportes,
  reparto prorrateado y desglose de sales tax en Core. −268 líneas Swift, catálogo 762 → 709 KB, app iOS −88 KB.
- Comprobado: 346 pruebas, iOS y macOS compilan, 25 pantallas del Mac iguales píxel a píxel antes y después.
- **Arreglo de paso (aprobado por el usuario):** Reportes › Sales tax sacaba las tasas en otro orden en cada arranque
  (líneas de impuesto = relación sin orden); ahora `ReportBuilder.salesTaxSummary` las ordena como `stableOrder`.
- Docs que se ven desactualizados (sin tocar): `README.md` (conciliación y recibos como pendientes, iCloud),
  `DISEÑO.md` («nada implementado»), y `REDISEÑO-NATIVO.md`/`DISEÑO.md` nombran tokens ya borrados.

## Chat de antes (14 y 15-nov)

- **Icono χρ (build 45, `55add7e`, 14-nov):** el `AppIcon.icon` del usuario (χ blanca y ρ azafrán `#F2B33D` sobre el
  degradado índigo) copiado tal cual a `App/AppIcon.icon`. Dentro de la app, `LogoMark` dibuja lo mismo con `ChiGlyph`
  y `RhoGlyph` (`DesignSystem/ChiGlyph.swift`, generados de los dos `<path>` del SVG: si cambia el icono, regenerarlos)
  y `Palette.logoRho`. La bienvenida dibuja el contorno de la χ, luego el de la ρ, y las rellena. También el icono de la
  web y las capturas `bienvenida-es/en.jpg` de la guía. Detalle en CONTEXTO, «Ícono».
- **Build 46 (`786f6fa`, 15-nov):** la tabla de Clientes del iPad ya no pinta su fondo blanco y va sobre el gris de la
  pantalla, distinta de la barra lateral (el usuario las veía del mismo color). Visto en el simulador del iPad, claro y
  oscuro.
- **Ojo para el siguiente chat:** el 14 y el 15-nov trabajaron dos chats a la vez en `version-1.3`. Antes de tocar nada,
  `git fetch` y `git log origin/version-1.3 origin/main` para ver qué hizo el otro.
- **Truco de capturas de la guía en el Mac:** `defaultSize` no bastó para la ventana de 900×1040. Fijarla con
  `defaults write com.chirogra.qa.<nombre> "NSWindow Frame SwiftUI.WindowGroup<ChirograUI.ChirograRootView>-1-AppWindow-1"
  "300 0 900 1040 0 0 1920 1050 "` y arrancar con `-qa.alta 1 -qa.altaEstado TX -qa.altaCiudad Austin
  -qa.altaCiudadTasa 2 -qa.altaZip 78702`; recorte de 600 px de ancho desde (150, 48), 936 de alto en español y 918 en
  inglés.

## Lo que le toca al usuario

1. **Asignar el build 59** al grupo de testers externos del enlace público cuando Apple lo procese, y mandar más
   testers (Beta Family, Userbrain, UXtweak) con él. Traer aquí lo que digan.
1b. ~~Probar el 58 en su iPhone~~: **probado por él el 21-nov** («Idioma» abre Ajustes y Clientes sin avisos encimados).
2. **Probar el 52 en TestFlight:** el recorrido de cada pestaña, «Más › Ayuda › Ver el recorrido otra vez», y borrar los
   datos de ejemplo y crear su empresa (el recorrido tiene que volver). Si puede, con Reducir movimiento y VoiceOver,
   que no se han probado en un aparato.
3. **Instalar en el iPad** cuando quiera y, si sale el aviso de iCloud, mandar captura de «Detalles».
4. **Para la 1.4:** la clave de Anthropic y el proyecto de Supabase «chirogra» los pone él en los secretos (no crearlos
   ni buscarlos). Pregunta abierta: si la suscripción cuesta más con el asistente.
5. **Avisar cuando Apple apruebe la 1.0**, para preparar el envío de la 1.3.

## Lo siguiente

0. **Build 59: SUBIDO iOS+Mac a TestFlight (21-nov, `34f6cc0`), `version-1.3` empujada.** Anular un cobro registrado por error
   (Eric, Beta Family: «un toque de más deja un cobro que no se puede borrar»). `Bookkeeper.voidPayment(_:on:)`
   revierte el asiento del cobro en su fecha (o en `on`, el primer día abierto, si su periodo está cerrado:
   `ClosedPeriodRetry` con `redate`), resta lo aplicado a cada factura y recalcula su estado, y los `BankTransaction`
   con `createdDocumentID` = cobro o `matchedEntryID` = su asiento vuelven a «Por revisar». **Sin campo nuevo** (no
   cambia el esquema de CloudKit): anulado = asiento revertido (`isVoided`, `voidDate(of:)`); el cobro y su
   `PaymentApplication` se quedan para el historial. Bitácora: evento `voidPayment` de la factura. Arreglos que
   hacían falta: base de caja (la reversión de un cobro reparte con el signo contrario), antigüedad a una fecha pasada
   (el anulado cuenta solo mientras estuvo vigente), `canEditIssued` ignora cobros anulados, «Cobrado en…» del Mac,
   «pagada el…» de Ventas, media de días de pago y el historial del cliente («Cobro anulado · F-1001», en gris).
   Pantalla: `InvoiceDetailView` (iPhone, iPad y Mac) con un paso por cobro en «Actividad» (`ActivityStep`), tocar uno
   vivo pide «¿Anular el cobro de $X del 22 oct?»; en «⋯», «Anular cobro…» (o submenú con varios). Inspector del Mac:
   «Cobro anulado de $X». `VoidPaymentTests` (5). Visto en el simulador «Chirogra QA 16e» (UITestsQA `AnularCobro`,
   sin commitear). Detalle visual sin cambiar: la confirmación sale como globo con flecha arriba (igual que «¿Anular la
   factura?»); el usuario puede pedir un aviso centrado.
0. **Build 58: SUBIDO iOS+Mac a TestFlight (21-nov, `944e0ad`).** Dos cosas del usuario con el 56/57 en su iPhone:
   (1) **Clientes** con un solo cliente y «Need attention» vacío: «All your clients are up to date» y la tarjeta
   «¿Llevas los libros de otro negocio?» van en la lista, pero `emptyState` iba en `.overlay` y pintaba «Nothing to
   handle» encima de las dos. Ahora `showsFilterEmpty` (filtro «Necesitan atención» o «Al día» sin nadie, sin búsqueda y
   sin `showsAllGood`) pone `filterEmptyNote` como sección de la lista en el iPhone; en la tabla (iPad/Mac) sigue en la
   capa, sin pisarse con nada. «Al día» vacío dice «Ningún cliente está al día · Todos tienen algo pendiente: míralos en
   «Necesitan atención».» (antes «Nada que atender», falso). El fallo venía de antes del 56. (2) **Idioma:** no
   encontraba dónde cambiarlo. La app no lo cambia por código (`AppLanguage`); se cambia en Ajustes › Apps › Chirogra ›
   Idioma (Mac: Ajustes del Sistema › General › Idioma y región › Aplicaciones). La fila «Idioma» de Más › Moneda y
   formatos era solo lectura; ahora es `AppLanguageRow(title: "Idioma", showsIcon: false)`, la misma fila del alta
   (abre `UIApplication.openSettingsURLString`; en el Mac «Cambiar…»), y el pie dice dónde se cambia. Probado en el
   simulador (`Build57Clientes`, `Build58Idioma`); Debug instalado en su iPhone antes de subir.
0a. **Build 57: SUBIDO iOS+Mac a TestFlight (21-nov, `c13f955`).** El usuario mandó una captura del 56 en su iPhone: en
   «Nuevo gasto › Recibo» los tres botones salían amontonados y centrados en **una sola fila**. Causa (del build 54,
   `801e8c3`): `.recorridoObjetivo("expense.receipt").id("expense.receipt")` sobre `ReceiptPickerButtons`, que da
   varias filas; en un `Form`, `.id` sobre una vista así las junta en una. Arreglo: `ReceiptPickerButtons(objetivo:)`
   pone el objetivo solo en el primer botón (escanear si hay `DocumentScanner`; si no, la foto) con el modificador
   privado `ObjetivoDelRecorrido`. Revisados los otros 34 objetivos con `.id`: todos van sobre una sola fila. Probado
   en el simulador (UITestsQA `Build56Recibo`, sin commitear): filas separadas y el paso «Receipt 7 of 8» del
   tutorial completo ilumina el primer botón. **Regla:** no poner `.recorridoObjetivo(...).id(...)` sobre una vista
   que dé varias filas dentro de un `Form`/`List`.
0b. **Build 56: SUBIDO iOS+Mac a TestFlight (21-nov, `130588b`).** Informe de Beta Family de **Eric** con el 55 (gratis; iPhone 13,
   iOS 27.2.1; facilidad 5/5, app 3/5, **recomendación 2/5**: «no security assurances, very few safeguards», «parece hecho
   con IA» por los recorridos incoherentes). Sin fotos ni bugs en el xlsx. Hecho con un agente por arreglo (worktrees;
   ojo: los worktrees nacen de `main`, hay que avanzarlos a `version-1.3` y aplicar el trabajo sin commitear como parche).
   **Arreglos del informe:** (1) **Impuestos** usa la frecuencia de la agencia (mensual/trimestral/anual;
   `SalesTaxShownPeriod`, `salesTaxFilingPeriods`); antes siempre trimestral. (2) **Confirmación antes de registrar un
   cobro** en el detalle de la factura (`confirmationDialog`); no en la hoja del iPad/Mac ni en Banca. Anular un cobro:
   hecho en el build 59 (punto 0). (3) **Recibo en
   grande** al tocarlo (Quick Look, `ReceiptPreview`), también al crear el gasto y el W-9. (4) **PDF en grande** desde la
   miniatura de Enviar/Recordatorio (pastilla «Ver»). (5) Hoja del **recordatorio** con «Recordatorio de pago · vence…
   · saldo» arriba; el botón siempre «Recordatorio» con campana, azul («enviado hoy» aparte). (6) **Recorrido:** deslizar
   la tarjeta adelante/atrás y un solo indicador «n de m». (7) **«Cómo protege Chirogra tus libros»** (Más › Seguridad y
   un paso del recorrido de Más; cada frase comprobada en el código; la copia de seguridad no lleva contraseña y
   restaurar una vieja reemplaza la bitácora). (8) Aviso al editar una factura emitida corregido (no siempre revierte).
   **Repaso visual (capturas antes/después vistas por el usuario):** indicador «n de m» también en bienvenida y alta
   (`PasoIndicador`); inglés con **Title Case** en botones/menús/títulos y frase en mensajes, diálogos y etiquetas;
   «empresa» = **business**; **«cobro»** para facturas y «pago» para proveedores e impuestos; títulos grandes en Ventas
   y listas de Más; **misma cabecera en todos los detalles** (`DetailSummary`; cliente y proveedor **con el círculo de
   iniciales**, decidido por el usuario el 21-nov); `Metrics.tileRadius`, tarjetas del recorrido con `cardRadius`;
   botones sueltos con los estilos de la app; Por pagar «Programado para…» en dos líneas. **Menores (pedido meterlos
   en el 56):** colores de estado (vencido rojo, borrador gris, informativos azul: el canvas tenía «Programada» en Tinta y
   «Recurrente» en verde azulado), `ListSummaryHeader` en Ventas/Estimados/Clientes, `NoResultsView` en todas las
   listas, `Metrics.stateIcon`, «Borrar» en vez de «Eliminar», iconos (enviar = avión; PDF = `doc.badge.arrow.up`;
   exportar = compartir), deslizar con icono y texto, filtros en plural, fechas con los ayudantes de la app (también
   Formatos y copias), «Profit and Loss» igual en fila y título, subtítulo «Empresa · base», gráficas de Reportes con los
   colores de Inicio (`Palette.income`/`expense`, `previousPeriod`). **Sin cambiar (una opinión):** el sales tax en
   Gastos; «ya no es novedad en 2026». **Ojo pruebas:** la de Vision del recibo (`ReceiptReaderTests`) falla a veces con
   el Mac cargado (simuladores a la vez); sola pasa.

0. **Build 55: SUBIDO iOS+Mac a TestFlight (20-nov, `216d429`).** Informe de Beta Family de Yurii S. con el 54 (pago;
   iPhone 16e, iOS 26.7.1, formato de Ucrania, oscuro; 4/5, recomendación 4/5, **facilidad 2/5**). Test con 4 tareas
   y 5 preguntas (texto en inglés y español dado en el chat; «About the app» y «What to test» tienen que ser distintos).
   (1) **Campos de dinero:** al volver a un campo con importe, lo tecleado se pegaba detrás de «US$» («10,99 US$80» en el
   descuento, «1,00 US$896253» en «Tax included»; reproducido en el 54: el importe no cambiaba, y en EE. UU. «$510.99»).
   Arreglo en `MoneyField`: al editar, solo el número («10,99»); al salir, con la moneda; lee coma o punto decimal
   (`MoneyField.minorUnits(from:locale:)`, pruebas en `MoneyFieldTests`). Sin `onAppear` (las pruebas con
   `ImageRenderer` se caían). Probado en el simulador (precio, descuento, impuesto incluido; uk_UA y en_US).
   (2) Pidió **difuminado** al empezar el tutorial completo: la primera tarjeta de cada recorrido (sin nada iluminado)
   lleva `.ultraThinMaterial` debajo del velo; visto en oscuro y claro. (3) Sin cambio: en la tarea 4 hizo una
   **factura** de $40 en vez de un gasto y dio su total como «impuesto que debo» (vigilar si otro se confunde igual);
   lo más difícil, cobrar el resto de una factura pagada a medias; pide vídeo tutorial con un caso real y ajustes de
   otros países (Ucrania). Recordatorio de pago: «easy»; tarjetas que tapan: no; tutorial completo: «about right».
   **Pendiente aparte:** `ScreenSmokeTests` se cae en este Xcode (`ImageRenderer`, «no current update to enqueue action
   to») ya con el 54; las demás pruebas de UI pasan con `--skip ScreenSmokeTests`.

0. **Build 54: SUBIDO iOS+Mac a TestFlight (20-nov, `801e8c3`, EMPUJADO): «Tutorial completo»**, arreglo de iOS 27
   y títulos de Inicio a la vista. Pedido del tester Yurii S. («too short», quería todos los botones),
   decidido así por el usuario: el recorrido corto de la primera vez **no cambia**; en **Más › Ayuda** hay un
   interruptor «Tutorial completo» que, al encenderlo, lleva a Inicio y empieza, y desde ahí **cada pantalla explica todos
   sus botones la primera vez que se abre** (solo iPhone, como el corto). Pantallas: las 5 pestañas (Inicio 12 pasos)
   más factura, estimado, editor de factura/estimado, editor de gasto, reportes e impuestos. Código:
   `DesignSystem/RecorridoAFondo.swift` (los pasos), `Recorrido` (`aFondo`, `activarAFondo`, `fondoKey` solo local,
   `recorridoPantalla(_:)`, `recorridoEnHoja()` puesto en `editorSheetSizing` para que el velo tape la barra de la hoja,
   `recorridoDesplazable()`, marcos que se borran al desaparecer la vista). «Ver el recorrido otra vez» lo apaga (es el
   corto). Con más de 7 pasos el indicador es «3 de 12» (los puntos partían «Siguiente» en tres líneas). 101 textos
   nuevos con su inglés en `Localizable.xcstrings`. Probado en el simulador «Chirogra QA 16e» con `-qa.recorrido afondo`
   (UITestsQA `AFondoQA` en la copia, sin commitear): Inicio 12, Ventas 6, factura 6, editor 7, Gastos 6, gasto 8,
   Banca 5, Más 8, reporte 5, impuestos 5, estimado 6; el corto sigue igual (Inicio 4, Más 3) y el interruptor lleva a
   Inicio con sus 12. «Escanear recibo» solo sale en un iPhone de verdad (el simulador no tiene escáner). Arreglos de
   paso: los marcos se vuelven a medir al reaparecer la vista (al volver a una pestaña no se medían y Inicio se quedaba
   en 4 pasos) y lo «a la vista» se mide con el alto de la ventana (el del velo era 81 pt menor y saltaba «Ayuda» y
   «Recibo»). `-qa.recorrido reset` apaga también el tutorial completo. Tests del paquete: 177 + 75, ninguno falla.
   **20-nov, también para el 54:** informe de Beta Family de Jiga T. (pago; iPhone 13 mini, **iOS 27.0**; 5/5,
   facilidad 5/5): los recorridos le ayudaron y la duración bien; «some tour messages covered parts of the screen» (3
   veces); lo más difícil, el alta y factura/cobro («several details»); pide explicar mejor los cálculos de impuestos,
   reportes más detallados, recibos más fáciles y recordatorios de pago. Reproducido en simuladores nuevos «Chirogra QA
   13 mini» (`7E4B8334`, iOS 27.0) y «Chirogra QA 16e iOS27» (`7E1E106C`): **en iOS 27 los pasos de botones de la barra
   de arriba buscados por `ax:` desaparecían** (Banca «Trae tu banco», Guardar del gasto…): la etiqueta ya no está en
   la vista de UIKit sino en un elemento de accesibilidad dentro de `UIKitBarItemHost`. Arreglado en
   `Recorrido.marcoEnVentana` (mira también `accessibilityElements` y su `accessibilityFrame`); comprobado en iOS 27 y
   26.5 (Banca 3 / 5, gasto 8). Lo de «tapar» en el 13 mini: la tarjeta queda pegada encima de lo iluminado y tapa el
   título de su sección (Taxes, Receivables / See all, To pay). **Arreglado (opción A, elegida por el usuario):** en
   Inicio del iPhone, `HomeView.group(_:recorrido:content:trailing:)` junta título y tarjeta y el recorrido ilumina los
   dos (`home.salesTax`, `home.chart`, `home.receivables`, `home.payables`, `home.accounts`); el aspecto de Inicio no
   cambia. Visto en el 13 mini (antes y después en el scratchpad de ese chat); macOS compila; 177 + 75 pruebas.

0. **Build 53: SUBIDO iOS+Mac a TestFlight (18-nov, `a5f6468`), `version-1.3` EMPUJADA.** Informe de Beta Family de Yurii S. (pago; el mismo del 52, ahora con el 51): 4/5, facilidad 3/5. (1) Fila de factura pagada a medias ilegible con formato europeo y letra XL → `InvoiceRow` con `ViewThatFits` («of $X» en su línea) y subtítulo en 2 líneas. (2) «Ver el recorrido otra vez» empezaba por Más («vi solo el final») → `Recorrido.pedidoInicio`, `RootView` va a Inicio. (3) Sus capturas: lista de Ventas cortada al 60 % y barra de Total/Issue flotando a la altura del teclado, sin teclado a la vista; NO reproducido en el simulador (16e, iOS 26.5, XL, uk_UA, oscuro, buscador, precio). Defensa: `ignoringStaleKeyboardSpace` en las pestañas y `ignoresSafeArea(.keyboard)` sin `keyboardWillShow` en el editor y `bottomBarHiddenWithKeyboard`. Preguntarle si usa teclado de otra app, Bluetooth o dictado. Dijo además: recorrido «too short» (querría todos los botones; no alargarlo), la usaría en ucraniano. Simulador de QA nuevo «Chirogra QA 16e» (`44631678`). Los testers gratis de Beta Family no contestan las preguntas metidas dentro de una tarea: cada pregunta, aparte. UXtweak gratis: una sola tarea (First Click sobre `03-gastos-en.png`, alquiler mensual → «Recurring»).

0. **Build 52: SUBIDO iOS+Mac a TestFlight (18-nov, `5643a27`), `version-1.3` EMPUJADA.** Un tester de Beta Family vio el recorrido con la empresa de ejemplo y pidió «el tutorial para mi propio negocio» y «entrar con Apple o Google o como invitado». Arreglos: (1) al borrar los datos de ejemplo (`SampleBooks.discard`, caso `isSample`) se llama a `Recorrido.olvidarTodo()` y la empresa propia vuelve a ver el recorrido (con varias empresas reales no se toca); (2) en `AudiencePage` (última página, donde cae «Saltar») una línea con candado: «Sin cuenta ni contraseña…» / «No account or password…». Probado en el simulador (UITestsQA `Build52QA`, sin commitear): ejemplo → recorrido visto → no se repite → borrar → empresa nueva → sale otra vez. Ojo: `xcodegen` quita `ubiquity-kvstore-identifier` de `App/Chirogra.entitlements`; en la copia de subida se restauró con `git checkout`.

0a. **Build 51: recorrido de la primera vez, en `version-1.3` (17-nov), SUBIDO iOS+Mac a TestFlight** (EMPUJADO en `3ce3df8`). El usuario vio que otras apps enseñan cada pantalla la
   primera vez; se hizo una muestra, Claude Design dibujó 3 estilos (canvas «Chirogra — First-run tour»,
   claude.ai/artifact/NYauYUc8B2M7zu1mir9yYP) y el usuario eligió la **A «Foco»** y dijo «Hazlo».
   - `DesignSystem/Recorrido.swift`: la primera vez que se abre cada pestaña del iPhone (Inicio 4 pasos con «Primeros
     pasos» si la empresa es nueva, Ventas 5, Gastos 4, Banca 3, Más 3) se oscurece la pantalla, se ilumina una parte
     y una tarjeta con flecha la explica. «Saltar» o el último paso lo dan por visto (UserDefaults + iCloud KVS).
     Tiempos de la ficha del canvas; anillo que late 2 veces; Reducir movimiento = fundido; VoiceOver: foco en la
     tarjeta, tocar fuera no avanza, escape cierra; letra grande: «Paso 2 de 5» y botones apilados, y la tarjeta
     siempre cabe en la pantalla. Los botones de la barra se buscan en UIKit por su nombre de accesibilidad (`ax:`).
   - «Más › Ayuda › Ver el recorrido otra vez» (`repetirTodo`). Se quitó `CustomizeTabsTip` (lo enseña el recorrido
     de Más); `TaxesTip` y `RecurringTip` salen después del recorrido de su pestaña.
   - QA: `-qa.recorrido reset` lo borra; con otros `-qa.*` y sin `-qa.recorrido` no sale (capturas de la tienda).
   - Comprobado en el simulador (español e inglés, empresa de ejemplo y nueva, letra grande, oscuro, repetir desde
     Más); 346 pruebas; iOS y macOS compilan; 39 textos nuevos traducidos. Capturas y vídeo en
     `~/Desktop/Chirogra-capturas-51`. Reducir movimiento y VoiceOver están programados pero no probados en un aparato.

0b. **Build 50: SUBIDO iOS+Mac a TestFlight (17-nov, `9f32335`), `version-1.3` y `main` EMPUJADAS (web con «Kairogra»).** Tras el 5.º tester de Userbrain
   (el primero con el 49; le dio 6–7 sobre 10) y las capturas del usuario del aviso de iCloud, que les salía a todos:
   - **Aviso de iCloud:** franja de una línea con «×» que se cierra en todas las pestañas (`SyncMonitor.dismissBanner`);
     antes de enseñar un fallo se pregunta a CloudKit por la cuenta (`accountStatus`): sin cuenta (o iCloud apagado para
     Chirogra) sale como nota azul «Tus libros se guardan en este aparato», que se cierra para siempre; textos propios
     para iCloud lleno y cuenta por revisar; «Detalles» con dominio y número del error (`failureCode`). Sospecha: los
     testers no tienen iCloud para la app (sin cuenta llega `NSCocoaErrorDomain 134400`, que el 49 no reconocía). Sin
     comprobar en un aparato real: pendiente que el usuario instale el 49/50 en su iPad. QA: `-ChirograForceSync
     sinCuenta|fallo`.
   - **Cobro:** «Marcar como pagada · $X» (parcial: «Registrar cobro de $X»); tocar «Pago · Pendiente» o «Pagada» en
     Actividad lleva al botón (el tester tocaba esos círculos). El cobro funcionaba: reproducido en el simulador.
   - **Precio de la factura:** la barra del teclado (la de «Listo») tapaba la fila del precio y los toques se perdían
     (visto en el simulador); escribiendo la descripción, la barra lleva «Precio», que pasa el foco al precio.
   - «Registrar gasto» en la ficha de una cuenta de Banca (`RecordExpenseButton`), con esa cuenta de pago.
   - «Por cobrar $X» en grande en Ventas; texto de borrar los datos de ejemplo: «No se borra nada tuyo».
   - Comprobado: 346 pruebas, iOS y macOS compilan, catálogo traducido, capturas en ~/Desktop/Chirogra-capturas-50.
0. **Build 49: SUBIDO a TestFlight iOS y macOS (16-nov noche), commit `292f269` en `version-1.3`, sin empujar.** Decisiones del usuario: 7 días de uso
   libre, consejo para personalizar la barra (no cambiar las pestañas de entrada), pronunciación en bienvenida, tienda,
   web y tarea de Userbrain. Lo hecho:
   - **Uso libre de 7 días** (`SubscriptionStore.freeUseDays`): quien nunca se ha suscrito registra sin hoja de planes
     desde su primera empresa (fecha más antigua de los libros, guardada también en el almacén de clave-valor de
     iCloud, `freeUse.start`); después, solo lectura y la hoja dice «Tus 7 días de uso libre terminaron…». Ajustes
     enseña «Uso libre: quedan N días». QA: `-qa.suscripcion libre|nueva`.
   - Los «Primeros pasos» de Inicio pasan por `whenWritable` (por ahí le salió el error al 3.er tester); el error de
     solo lectura ya no dice «terminó» a quien nunca se suscribió (`Bookkeeper.readOnlyCanStartTrial`).
   - **Factura de $0:** «El total de la factura es $0.00» con «Emitir de todos modos» en el editor, el detalle y la
     tabla del Mac (`confirmsZeroTotalIssue`).
   - **Lo que falta:** gasto y factura con el botón siempre activo y aviso «Para guardar, falta: …»
     (`MissingFields`); en el alta, la línea «Para continuar, falta: …» bajo el botón.
   - **iCloud:** la franja de error solo sale si el fallo dura 20 s sin un evento bueno (`SyncMonitor.failureGrace`);
     sin cuenta de iCloud, enseguida y con texto propio («iCloud no está activado»).
   - **Barra del iPhone:** pista `CustomizeTabsTip` arriba de Más (en `TipGroup` con la de Impuestos, de una en una);
     en Personalizar › Pestañas, al añadir, la lista sube a «Así se verá» y vibra.
   - **«Se pronuncia «Kairogra»»** bajo el nombre en la bienvenida (en inglés «Pronounced “KY-roh-grah”»), en la web
     (`sitio/`, se publica al empujar `main`) y en la descripción de la tienda (APP-STORE.md, para el envío de la 1.3).
   - Comprobado: 346 pruebas, catálogo sin textos por traducir, capturas del simulador del iPhone (bienvenida, alta,
     uso libre, pista de Más, gasto incompleto, fin del uso libre); macOS compila. Lo siguiente: que el usuario lo pruebe y más testers de Userbrain con el 49.
   Lo que dijeron los testers (para el registro):
   - **Avisar antes de emitir una factura de $0** («This invoice total is $0.00. Issue anyway?»): el 2.º tester emitió
     una de $0 sin darse cuenta y tuvo que duplicarla.
   - Lo que salga de los nuevos tests de Userbrain con el 48. **El usuario quiere esperar a más testers y arreglarlo
     todo de una vez** (16-nov). Lo del **3.er tester** (con el 48; factura, gasto y pestañas le resultaron fáciles):
     - **Suscripción (3 de 3 testers tropiezan):** cerró la hoja de planes, al poner el saldo del banco en el alta le
       salió el error «Your books are read-only because your subscription ended» (sin haberse suscrito nunca: el texto
       de `BookkeepingError.readOnly` en `Bookkeeper.swift` no mira `canStartTrial`, y sale como alerta de error en vez
       de abrir la hoja de planes) y tuvo que suscribirse para seguir. Le confundió «Restore» y buscó un código.
       Propuesto: que guardar sin suscripción abra la hoja con «Empieza tu prueba gratis» (eso va seguro), y decidir
       si se deja registrar unos días antes de pedirla. Sin build: decir en la tarea de Userbrain que TestFlight no cobra.
     - **Reportes lejos** (tuvo que ir a Más y bajar): propuesto Ventas, Gastos y Reportes como pestañas de entrada
       (hoy Ventas, Gastos y Banca, `PhoneShortcuts.defaultTabs`), o Reportes como favorito arriba de Más.
     - Comentarios sueltos: el aspecto «más vibrante» y le costó pronunciar «Chirogra». El asistente con IA quedó
       en PLAN-2.0.md, «Ideas por estudiar».
     Lo del **4.º tester** (con el 48, datos de ejemplo; empezó la prueba gratis sin problema tras leer «You will not
     be charged»; Inicio en color le bastó para ver cómo iba el negocio; factura, gasto y pestañas fáciles):
     - **«We couldn't sync your data» nada más empezar.** `SyncMonitor.apply` (`SyncStatusViews.swift`) pone la franja
       con cualquier error de un evento de CloudKit, también los pasajeros que CloudKit reintenta solo. No se sabe el
       código. Propuesto: no enseñarla por errores que se reintentan solos salvo que duren, y un texto propio si no hay
       cuenta de iCloud.
     - **«It doesn't look like it changed it for me»** al cambiar Banca por Presupuesto contra real. **Comprobado en el
       simulador (16-nov): la barra sí cambia al momento** (sale «Budget»). Lo que confunde: la fila añadida desaparece
       de la vista (sube a «En la barra», fuera de pantalla) y en la barra el nombre es otro, más corto. Propuesto:
       al añadir, subir la lista hasta «En la barra» y una vibración.
     - **Campos obligatorios: segunda persona perdida** (en el gasto no sabía por qué no guardaba hasta poner el
       proveedor). Era la condición acordada para poner la línea «Falta: …» bajo el botón.
     - Le costó encontrar cómo registrar el cobro de la factura (al final lo vio en la factura: «user error»).
     - Segunda persona que querría más de 3 pestañas (sin darle importancia).
     - Idea: **citas o agenda con los clientes**, «todo en un solo sitio», como el programa que usa en su negocio.
     - Otra vez le costó pronunciar el nombre («KyraGra», «TriRobra»). **Se pronuncia «Kairogra»** (decisión del
       16-nov, en CONTEXTO); falta decidir dónde decirlo (tarea de Userbrain, bienvenida, tienda, web).
   - **1.4 con agenda y asistente con IA (decidido el 16-nov):** plan en [PLAN-1.4.md](PLAN-1.4.md). Rama
     `version-1.4` aparte; asistente con Claude a través de un servidor Supabase «chirogra» (base del de la 2.0);
     agenda con citas, cita → factura, recordatorios y Calendario. Lo primero: los trámites del usuario (clave de
     Anthropic, proyecto de Supabase) y el canvas de diseño. Decidido: 100 preguntas al mes, citas que se repiten
     desde el principio y el modelo (Opus 5.5 o Sonnet 5.5) tras medir en la QA.
   - Si el usuario lo decide: la suscripción después de un tiempo de uso, no al crear la empresa.
1. **Cuando aprueben la 1.0: enviar directo la 1.3** (decisión del 13-nov), con su último build. Preparar entonces un
   «What's New» que junte 1.1, 1.2 y 1.3 (las tres partes están en [APP-STORE.md](APP-STORE.md)), las notas para el
   revisor juntas, el plan para contadores en el envío y las capturas (`00-bienvenida` y `06-panel-clientes` en el
   escritorio, y las que falten). **Revisar que las capturas enseñen el logo χρ:** las hechas antes del 14-nov
   llevan la χ sola.
2. **Probar en TestFlight el último build de la 1.3** antes de enviarla.
3. **Tasas por código postal: cada trimestre** (1 ene, 1 abr, 1 jul, 1 oct) correr `scripts/tasas/descargar.sh` y
   `generar.py` y subir un build (DATOS-V5.md). Faltan AL AK AZ CO HI ID LA MO MS NM PA SC VA.
4. **2.0 con servidor:** plan en [PLAN-2.0.md](PLAN-2.0.md). Ya se pueden hacer los trámites (equipo «Chirogra» en
   Plaid con producción y Statements, cotizaciones de Gusto Embedded y Check, perfil en Stripe Connect); el código
   empieza cuando la 1.3 esté en la tienda.

## Cómo se trabaja con este usuario

- Commit, push y subir builds **solo cuando lo pida**.
- Probar en copias, nunca en sus datos: simuladores `B8931A17` (iPhone) y `ADB9E3BB` (iPad); en el Mac, una copia con
  otro bundle id, firmada ad hoc y sin iCloud. **No tocar el simulador `BEB1EA39`** (es de Tamio).
- No mover el ratón del Mac, no cambiar ajustes del sistema ni de Xcode, no buscar claves, avisar antes de borrar.
- En su iPhone, para enseñarle algo sin tocar su app: la copia «Chirogra Prueba» (`com.chirogra.qa.bienvenida`).
- Para decisiones de diseño, mostrarle muestras reales (capturas de la app) antes de cambiar algo que él ya decidió.
- Subir un build: `CURRENT_PROJECT_VERSION` en `project.yml` y en el pbxproj, clon limpio del commit (`git clone
  --no-local`), `xcodebuild archive` (iOS y macOS, `DEVELOPMENT_TEAM=4N9XEU7F4P -allowProvisioningUpdates`) y
  `-exportArchive` con `method app-store-connect`, `destination upload` (CONTEXTO, «Subir un build»).
- En un simulador nuevo: `-iCloudSyncEnabled NO` (sin cuenta de iCloud, CloudKit cierra la app) y `-qa.suscripcion
  activa` (si no, la pantalla de planes tapa Inicio).
